# frozen_string_literal: true

# BroadcastReliabilityService provides reliable message broadcasting with retry mechanisms
# and priority-based queuing for ActionCable messages. This service ensures critical
# sync status updates are delivered even when the broadcasting infrastructure encounters issues.
#
# Usage:
#   # Direct broadcasting with retry
#   BroadcastReliabilityService.broadcast_with_retry(
#     channel: SyncStatusChannel,
#     target: sync_session,
#     data: { status: 'processing' },
#     priority: :medium
#   )
#
#   # Queued broadcasting via Sidekiq
#   BroadcastReliabilityService.queue_broadcast(
#     channel: 'SyncStatusChannel',
#     target_id: sync_session.id,
#     target_type: 'SyncSession',
#     data: { status: 'processing' },
#     priority: :high
#   )
module Services
  class Services::BroadcastReliabilityService
  # Priority levels determine retry behavior and queue priority
  PRIORITIES = {
    critical: { max_retries: 5, backoff_base: 0.5, queue: "critical" },
    high: { max_retries: 4, backoff_base: 1.0, queue: "high" },
    medium: { max_retries: 3, backoff_base: 2.0, queue: "default" },
    low: { max_retries: 2, backoff_base: 4.0, queue: "low" }
  }.freeze

  class BroadcastError < StandardError; end
  class InvalidPriorityError < StandardError; end

  class << self
    # Broadcast a message with automatic retry on failure
    # @param channel [Class, String] The ActionCable channel class or name
    # @param target [Object] The target object to broadcast to
    # @param data [Hash] The data to broadcast
    # @param priority [Symbol] Priority level (:critical, :high, :medium, :low)
    # @param attempt [Integer] Current attempt number (internal use)
    # @param request_ip [String] Optional request IP for rate limiting
    # @param user_id [String] Optional user ID for rate limiting
    # @return [Boolean] Success status
    def broadcast_with_retry(channel:, target:, data:, priority: :medium, attempt: 1, request_ip: nil, user_id: nil)
      puts "[BROADCAST_DEBUG] Starting broadcast_with_retry with priority: #{priority}"
      Rails.logger.debug "[BROADCAST_DEBUG] Starting broadcast_with_retry with priority: #{priority}"
      validate_priority!(priority)
      puts "[BROADCAST_DEBUG] Priority validated"
      Rails.logger.debug "[BROADCAST_DEBUG] Priority validated"

      # Security validation and rate limiting (only on first attempt)
      if attempt == 1
        # Use feature flag to control security validation
        if BroadcastFeatureFlags.enabled?(:broadcast_validation)
          Rails.logger.debug "[BROADCAST_DEBUG] Security validation enabled"
          result = validate_broadcast_security(channel, target, data, priority, request_ip, user_id)
          return false unless result
        else
          Rails.logger.debug "[BROADCAST_DEBUG] Security validation disabled"
        end
      end

      priority_config = PRIORITIES[priority]
      start_time = Time.current

      result = begin
        Rails.logger.debug "[BROADCAST_DEBUG] Performing broadcast"
        # Perform the actual broadcast
        perform_broadcast(channel, target, data)

        Rails.logger.debug "[BROADCAST_DEBUG] Broadcast successful, recording analytics"
        # Log successful broadcast
        BroadcastAnalytics.record_success(
          channel: channel_name(channel),
          target_type: target.class.name,
          target_id: target.id,
          priority: priority,
          attempt: attempt,
          duration: (Time.current - start_time).to_f
        )

        Rails.logger.debug "[BROADCAST_DEBUG] Returning true"
        true
      rescue StandardError => e
        # Log the failure
        BroadcastAnalytics.record_failure(
          channel: channel_name(channel),
          target_type: target.class.name,
          target_id: target.id,
          priority: priority,
          attempt: attempt,
          error: e.message,
          duration: (Time.current - start_time).to_f
        )

        # Retry logic
        if attempt < priority_config[:max_retries]
          delay = calculate_backoff_delay(priority_config[:backoff_base], attempt)
          Rails.logger.warn "[BROADCAST] Retrying broadcast in #{delay}s - Attempt #{attempt}/#{priority_config[:max_retries]}: #{e.message}"

          sleep(delay)
          return broadcast_with_retry(
            channel: channel,
            target: target,
            data: data,
            priority: priority,
            attempt: attempt + 1,
            request_ip: request_ip,
            user_id: user_id
          )
        else
          Rails.logger.error "[BROADCAST] Failed to broadcast after #{priority_config[:max_retries]} attempts: #{e.message}"
          BroadcastErrorHandler.handle_final_failure(channel, target, data, priority, e)
          false
        end
      end

      result
    end

    # Queue a broadcast job for background processing
    # @param channel [String] The ActionCable channel class name
    # @param target_id [Integer] The target object ID
    # @param target_type [String] The target object class name
    # @param data [Hash] The data to broadcast
    # @param priority [Symbol] Priority level (:critical, :high, :medium, :low)
    def queue_broadcast(channel:, target_id:, target_type:, data:, priority: :medium)
      validate_priority!(priority)

      BroadcastJob.enqueue_broadcast(
        channel_name: channel,
        target_id: target_id,
        target_type: target_type,
        data: data,
        priority: priority
      )
    end

    # Get priority configuration
    # @param priority [Symbol] Priority level
    # @return [Hash] Priority configuration
    def priority_config(priority)
      PRIORITIES[priority] || raise(InvalidPriorityError, "Invalid priority: #{priority}")
    end

    private

    # Perform the actual ActionCable broadcast
    # @param channel [Class, String] The channel class or name
    # @param target [Object] The target object
    # @param data [Hash] The data to broadcast
    def perform_broadcast(channel, target, data)
      channel_class = channel.is_a?(String) ? channel.constantize : channel

      # Use broadcast_to for object-specific broadcasts
      channel_class.broadcast_to(target, data)
    rescue StandardError => e
      raise BroadcastError, "Broadcast failed: #{e.message}"
    end

    # Calculate exponential backoff delay
    # @param base [Float] Base delay in seconds
    # @param attempt [Integer] Current attempt number
    # @return [Float] Delay in seconds
    def calculate_backoff_delay(base, attempt)
      # Exponential backoff: base * (2 ** (attempt - 1)) with jitter
      delay = base * (2 ** (attempt - 1))
      jitter = rand(0.0..0.5) * delay
      delay + jitter
    end

    # Validate priority parameter
    # @param priority [Symbol] Priority level to validate
    # @raise [InvalidPriorityError] if priority is invalid
    def validate_priority!(priority)
      Rails.logger.debug "[BROADCAST_DEBUG] validate_priority! called with: #{priority.inspect}"
      return if PRIORITIES.key?(priority)

      Rails.logger.debug "[BROADCAST_DEBUG] Invalid priority detected, raising error"
      raise InvalidPriorityError, "Invalid priority '#{priority}'. Valid priorities: #{PRIORITIES.keys.join(', ')}"
    end

    # Extract channel name from class or string
    # @param channel [Class, String] The channel
    # @return [String] Channel name
    def channel_name(channel)
      channel.is_a?(String) ? channel : channel.name
    end

    # Validate broadcast security and apply rate limiting
    # @param channel [Class, String] The ActionCable channel class or name
    # @param target [Object] The target object to broadcast to
    # @param data [Hash] The data to broadcast
    # @param priority [Symbol] Priority level
    # @param request_ip [String] Optional request IP for rate limiting
    # @param user_id [String] Optional user ID for rate limiting
    # @return [Boolean] True if validation passes
    def validate_broadcast_security(channel, target, data, priority, request_ip, user_id)
      # Prepare request data for validation
      request_data = {
        "channel_name" => channel_name(channel),
        "target_type" => target.class.name,
        "target_id" => target.id,
        "data" => data,
        "priority" => priority.to_s
      }

      # Input validation and sanitization
      validator = BroadcastRequestValidator.new(request_data)
      unless validator.valid?
        Rails.logger.warn "[BROADCAST_SECURITY] Validation failed: #{validator.errors.join(', ')}"

        # Log security event
        log_security_event("validation_failed", {
          errors: validator.errors,
          warnings: validator.warnings,
          channel: channel_name(channel),
          target_type: target.class.name,
          target_id: target.id,
          request_ip: request_ip,
          user_id: user_id
        })

        return false
      end

      # Rate limiting check (with feature flag)
      if should_apply_rate_limiting?(priority) && BroadcastFeatureFlags.enabled?(:enhanced_rate_limiting)
        identifier = user_id || "anonymous_#{request_ip}"
        rate_limiter = BroadcastRateLimiter.new(
          identifier: identifier,
          request_ip: request_ip
        )

        unless rate_limiter.allowed?(priority: priority)
          Rails.logger.warn "[BROADCAST_SECURITY] Rate limit exceeded: #{rate_limiter.errors.join(', ')}"

          # Log rate limiting event
          log_security_event("rate_limit_exceeded", {
            identifier: identifier,
            request_ip: request_ip,
            priority: priority,
            errors: rate_limiter.errors,
            retry_after: rate_limiter.retry_after(priority: priority)
          })

          return false
        end

        # Consume rate limit token
        rate_limiter.consume!(priority: priority)
      end

      # Log successful validation
      if validator.warnings.any?
        Rails.logger.info "[BROADCAST_SECURITY] Validation passed with warnings: #{validator.warnings.join(', ')}"
      end

      true
    rescue StandardError => e
      Rails.logger.error "[BROADCAST_SECURITY] Security validation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Fail closed - reject on security validation errors
      false
    end

    # Determine if rate limiting should be applied based on priority
    # @param priority [Symbol] Priority level
    # @return [Boolean] True if rate limiting should be applied
    def should_apply_rate_limiting?(priority)
      # Critical priority broadcasts may bypass rate limiting in emergencies
      # This can be controlled by configuration
      return false if priority == :critical && ENV["BYPASS_CRITICAL_RATE_LIMITING"] == "true"

      true
    end

    # Log security-related events for monitoring and analysis
    # @param event_type [String] Type of security event
    # @param data [Hash] Event data
    def log_security_event(event_type, data)
      event_data = {
        event_type: event_type,
        timestamp: Time.current.iso8601,
        service: "BroadcastReliabilityService"
      }.merge(data)

      Rails.logger.warn "[BROADCAST_SECURITY_EVENT] #{event_type}: #{event_data.to_json}"

      # Store security events for analysis (could be sent to security monitoring system)
      begin
        RedisAnalyticsService.increment_counter(
          "security_events",
          tags: { event_type: event_type, service: "broadcast" }
        )
      rescue StandardError => e
        Rails.logger.debug "[BROADCAST_SECURITY] Failed to record security metrics: #{e.message}"
      end
    end
  end
  end
end
