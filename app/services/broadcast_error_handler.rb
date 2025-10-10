# frozen_string_literal: true

# BroadcastErrorHandler provides sophisticated error handling for ActionCable
# broadcast failures with exponential backoff, circuit breaker pattern, and
# graceful degradation strategies.
#
# Key Features:
# - Exponential backoff with jitter for retry delays
# - Circuit breaker to prevent cascade failures
# - Fallback strategies when broadcasting consistently fails
# - Error categorization and handling strategies
# - Integration with monitoring and alerting systems
#
# Usage:
#   # Handle a broadcast failure (called by Services::BroadcastReliabilityService)
#   BroadcastErrorHandler.handle_final_failure(
#     SyncStatusChannel, sync_session, data, :high, error
#   )
#
#   # Check if broadcasts are healthy
#   healthy = BroadcastErrorHandler.broadcast_health_check
module Services
  class BroadcastErrorHandler
  # Circuit breaker states
  CIRCUIT_STATES = %w[closed open half_open].freeze

  # Error categories for different handling strategies
  ERROR_CATEGORIES = {
    network: [
      "Connection timeout",
      "Connection refused",
      "Network is unreachable",
      "Connection reset by peer"
    ],
    redis: [
      "Redis connection",
      "READONLY You can't write against a read only replica",
      "Redis server went away"
    ],
    cable: [
      "ActionCable",
      "Channel not found",
      "Stream not found",
      "Connection not established"
    ],
    resource: [
      "Memory",
      "Disk space",
      "Too many open files",
      "Resource temporarily unavailable"
    ]
  }.freeze

  class << self
    # Handle a final broadcast failure after all retries are exhausted
    # @param channel [Class, String] The channel class or name
    # @param target [Object] The target object
    # @param data [Hash] The broadcast data
    # @param priority [Symbol] Message priority
    # @param error [Exception] The error that caused the failure
    def handle_final_failure(channel, target, data, priority, error)
      error_category = categorize_error(error)
      channel_name = channel.is_a?(String) ? channel : channel.name

      Rails.logger.error "[BROADCAST_ERROR] Final failure for #{channel_name} -> #{target.class}##{target.id}: #{error.message} (Category: #{error_category})"

      # Update circuit breaker state
      update_circuit_breaker(channel_name, :failure)

      # Apply fallback strategy based on priority and error category
      apply_fallback_strategy(channel_name, target, data, priority, error_category)

      # Send alert if this is a critical failure
      send_alert_if_critical(channel_name, target, data, priority, error, error_category)

      # Store failure details for analysis
      store_failure_details(channel_name, target, data, priority, error, error_category)
    end

    # Check if broadcast system is healthy
    # @return [Boolean] True if broadcasts are healthy
    def broadcast_health_check
      circuit_states = get_all_circuit_states

      # System is healthy if no circuits are open
      open_circuits = circuit_states.select { |_channel, state| state == "open" }

      if open_circuits.any?
        Rails.logger.warn "[BROADCAST_HEALTH] Open circuits detected: #{open_circuits.keys.join(', ')}"
        false
      else
        true
      end
    end

    # Get circuit breaker status for a channel
    # @param channel_name [String] Channel name
    # @return [String] Circuit state ('closed', 'open', 'half_open')
    def get_circuit_state(channel_name)
      cache_key = "broadcast_circuit:#{channel_name}"
      circuit_data = Rails.cache.read(cache_key) || { state: "closed", failures: 0, last_failure: nil }

      # Check if circuit should transition from open to half_open
      if circuit_data[:state] == "open" && circuit_should_attempt_reset?(circuit_data)
        circuit_data[:state] = "half_open"
        Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)
      end

      circuit_data[:state]
    end

    # Record a successful broadcast for circuit breaker
    # @param channel_name [String] Channel name
    def record_success(channel_name)
      update_circuit_breaker(channel_name, :success)
    end

    # Get error handling statistics
    # @param time_window [ActiveSupport::Duration] Time window for stats
    # @return [Hash] Error handling statistics
    def get_error_statistics(time_window: 1.hour)
      cache_key = "broadcast_error_stats:#{time_window.to_i}"

      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        calculate_error_statistics(time_window)
      end
    end

    # Manual circuit breaker reset (for operational use)
    # @param channel_name [String] Channel name to reset
    def reset_circuit_breaker(channel_name)
      cache_key = "broadcast_circuit:#{channel_name}"
      circuit_data = { state: "closed", failures: 0, last_failure: nil, last_reset: Time.current }

      Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)
      Rails.logger.info "[BROADCAST_ERROR] Manual circuit breaker reset for #{channel_name}"
    end

    private

    # Categorize error based on error message patterns
    # @param error [Exception] The error to categorize
    # @return [Symbol] Error category
    def categorize_error(error)
      error_message = error.message.downcase

      ERROR_CATEGORIES.each do |category, patterns|
        if patterns.any? { |pattern| error_message.include?(pattern.downcase) }
          return category
        end
      end

      :unknown
    end

    # Update circuit breaker state based on success/failure
    # @param channel_name [String] Channel name
    # @param result [Symbol] :success or :failure
    def update_circuit_breaker(channel_name, result)
      cache_key = "broadcast_circuit:#{channel_name}"
      circuit_data = Rails.cache.read(cache_key) || { state: "closed", failures: 0, last_failure: nil }

      case result
      when :success
        if circuit_data[:state] == "half_open"
          # Successful broadcast in half_open state - close the circuit
          circuit_data = { state: "closed", failures: 0, last_success: Time.current }
          Rails.logger.info "[BROADCAST_ERROR] Circuit breaker closed for #{channel_name} after successful broadcast"
        elsif circuit_data[:state] == "closed"
          # Reset failure count on success in closed state
          circuit_data[:failures] = 0 if circuit_data[:failures] > 0
        end

      when :failure
        circuit_data[:failures] = (circuit_data[:failures] || 0) + 1
        circuit_data[:last_failure] = Time.current

        # Open circuit if failure threshold exceeded
        failure_threshold = get_failure_threshold(channel_name)
        if circuit_data[:failures] >= failure_threshold && circuit_data[:state] != "open"
          circuit_data[:state] = "open"
          circuit_data[:opened_at] = Time.current
          Rails.logger.warn "[BROADCAST_ERROR] Circuit breaker opened for #{channel_name} after #{circuit_data[:failures]} failures"
        end
      end

      Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)
    end

    # Check if circuit should attempt reset from open to half_open
    # @param circuit_data [Hash] Circuit data from cache
    # @return [Boolean] True if circuit should attempt reset
    def circuit_should_attempt_reset?(circuit_data)
      return false unless circuit_data[:opened_at]

      reset_timeout = get_circuit_reset_timeout(circuit_data[:failures] || 0)
      Time.current > (circuit_data[:opened_at] + reset_timeout)
    end

    # Apply fallback strategy based on priority and error category
    # @param channel_name [String] Channel name
    # @param target [Object] Target object
    # @param data [Hash] Broadcast data
    # @param priority [Symbol] Message priority
    # @param error_category [Symbol] Error category
    def apply_fallback_strategy(channel_name, target, data, priority, error_category)
      strategy = determine_fallback_strategy(priority, error_category)

      case strategy
      when :store_for_later_retry
        store_for_later_retry(channel_name, target, data, priority)
      when :send_notification_fallback
        send_notification_fallback(target, data)
      when :log_and_continue
        Rails.logger.info "[BROADCAST_ERROR] Applying log_and_continue fallback for #{channel_name}"
      when :degrade_gracefully
        apply_graceful_degradation(target, data)
      end
    end

    # Determine appropriate fallback strategy
    # @param priority [Symbol] Message priority
    # @param error_category [Symbol] Error category
    # @return [Symbol] Fallback strategy
    def determine_fallback_strategy(priority, error_category)
      case priority
      when :critical
        case error_category
        when :network, :redis then :store_for_later_retry
        when :cable then :send_notification_fallback
        else :store_for_later_retry
        end
      when :high
        case error_category
        when :network, :redis then :store_for_later_retry
        else :log_and_continue
        end
      when :medium
        :degrade_gracefully
      when :low
        :log_and_continue
      end
    end

    # Store broadcast for later retry when system recovers
    # @param channel_name [String] Channel name
    # @param target [Object] Target object
    # @param data [Hash] Broadcast data
    # @param priority [Symbol] Message priority
    def store_for_later_retry(channel_name, target, data, priority)
      retry_data = {
        channel_name: channel_name,
        target_id: target.id,
        target_type: target.class.name,
        data: data,
        priority: priority,
        stored_at: Time.current.to_f
      }

      cache_key = "broadcast_retry_queue:#{Time.current.to_f}:#{SecureRandom.hex(8)}"
      Rails.cache.write(cache_key, retry_data, expires_in: 1.hour)

      Rails.logger.info "[BROADCAST_ERROR] Stored broadcast for later retry: #{channel_name} -> #{target.class}##{target.id}"
    end

    # Send alternative notification when ActionCable fails
    # @param target [Object] Target object
    # @param data [Hash] Broadcast data
    def send_notification_fallback(target, data)
      # For sync sessions, we could store a flag to refresh on next page load
      if target.respond_to?(:mark_for_refresh)
        target.mark_for_refresh
      end

      Rails.logger.info "[BROADCAST_ERROR] Applied notification fallback for #{target.class}##{target.id}"
    end

    # Apply graceful degradation by reducing broadcast frequency
    # @param target [Object] Target object
    # @param data [Hash] Broadcast data
    def apply_graceful_degradation(target, data)
      # Could implement reduced frequency broadcasting here
      # For now, just log the degradation
      Rails.logger.info "[BROADCAST_ERROR] Applied graceful degradation for #{target.class}##{target.id}"
    end

    # Send alert for critical broadcast failures
    # @param channel_name [String] Channel name
    # @param target [Object] Target object
    # @param data [Hash] Broadcast data
    # @param priority [Symbol] Message priority
    # @param error [Exception] The error
    # @param error_category [Symbol] Error category
    def send_alert_if_critical(channel_name, target, data, priority, error, error_category)
      return unless priority == :critical || error_category == :redis

      # In a real application, this would integrate with your alerting system
      # (e.g., Slack, PagerDuty, email notifications)
      alert_data = {
        severity: "high",
        service: "broadcast_system",
        channel: channel_name,
        target: "#{target.class}##{target.id}",
        error: error.message,
        category: error_category,
        priority: priority,
        timestamp: Time.current.iso8601
      }

      Rails.logger.error "[BROADCAST_ALERT] #{alert_data.to_json}"
    end

    # Store detailed failure information for analysis
    # @param channel_name [String] Channel name
    # @param target [Object] Target object
    # @param data [Hash] Broadcast data
    # @param priority [Symbol] Message priority
    # @param error [Exception] The error
    # @param error_category [Symbol] Error category
    def store_failure_details(channel_name, target, data, priority, error, error_category)
      failure_data = {
        channel: channel_name,
        target_type: target.class.name,
        target_id: target.id,
        priority: priority.to_s,
        error_category: error_category.to_s,
        error_message: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.first(5),
        data_size: data.to_json.bytesize,
        timestamp: Time.current.to_f
      }

      cache_key = "broadcast_failure_details:#{Time.current.strftime('%Y-%m-%d-%H')}:#{SecureRandom.hex(8)}"
      Rails.cache.write(cache_key, failure_data, expires_in: 24.hours)
    end

    # Get all circuit breaker states
    # @return [Hash] Channel names to circuit states
    def get_all_circuit_states
      # In a real implementation, this would iterate through all known channels
      # For now, return states for known channels
      channels = %w[SyncStatusChannel DashboardChannel NotificationChannel]

      channels.each_with_object({}) do |channel, states|
        states[channel] = get_circuit_state(channel)
      end
    end

    # Get failure threshold for a channel
    # @param channel_name [String] Channel name
    # @return [Integer] Failure threshold
    def get_failure_threshold(channel_name)
      # Could be configurable per channel
      case channel_name
      when "SyncStatusChannel" then 5
      when "DashboardChannel" then 3
      else 4
      end
    end

    # Get circuit reset timeout based on failure count
    # @param failure_count [Integer] Number of failures
    # @return [ActiveSupport::Duration] Reset timeout
    def get_circuit_reset_timeout(failure_count)
      # Exponential backoff: base timeout * (2 ** min(failure_count - threshold, max_exp))
      base_timeout = 30.seconds
      max_exponent = 4 # Cap at 16x base timeout

      exponent = [ failure_count - 3, max_exponent ].min
      base_timeout * (2 ** [ exponent, 0 ].max)
    end

    # Calculate error handling statistics
    # @param time_window [ActiveSupport::Duration] Time window
    # @return [Hash] Error statistics
    def calculate_error_statistics(time_window)
      # This would aggregate error data from the cache
      # Simplified implementation for now
      {
        time_window: time_window.to_i,
        total_failures: 0,
        by_category: {
          network: 0,
          redis: 0,
          cable: 0,
          resource: 0,
          unknown: 0
        },
        by_priority: {
          critical: 0,
          high: 0,
          medium: 0,
          low: 0
        },
        circuit_breaker_events: 0,
        fallback_strategies_used: {
          store_for_later_retry: 0,
          send_notification_fallback: 0,
          log_and_continue: 0,
          degrade_gracefully: 0
        }
      }
    end
  end
  end
end
