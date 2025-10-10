# frozen_string_literal: true

# BroadcastFeatureFlags provides feature flag management for broadcast infrastructure
# allowing gradual rollout of new features and easy rollback in case of issues.
#
# Features:
# - Environment-based feature toggles
# - User/session-based rollout
# - A/B testing support
# - Circuit breaker pattern for unstable features
# - Fallback mechanisms
# - Usage analytics integration
#
# Usage:
#   BroadcastFeatureFlags.enabled?(:redis_analytics)
#   BroadcastFeatureFlags.enabled_for_user?(:new_rate_limiting, user_id: 123)
#   BroadcastFeatureFlags.with_fallback(:redis_metrics) { risky_operation }
module Services
  class Services::BroadcastFeatureFlags
  # Feature flag definitions with their configurations
  FEATURES = {
    # Redis-powered analytics
    redis_analytics: {
      default: false,
      description: "Use Redis for high-performance analytics instead of Rails cache",
      rollout_percentage: 0,
      circuit_breaker: true,
      fallback_method: :rails_cache_analytics
    },

    # Enhanced rate limiting
    enhanced_rate_limiting: {
      default: false,
      description: "Enable advanced rate limiting with IP blocking and abuse detection",
      rollout_percentage: 0,
      circuit_breaker: true,
      fallback_method: :basic_rate_limiting
    },

    # Input validation and sanitization
    broadcast_validation: {
      default: true,
      description: "Enable input validation and sanitization for broadcast requests",
      rollout_percentage: 100,
      circuit_breaker: false,
      fallback_method: :skip_validation
    },

    # Failed broadcast recovery
    failed_broadcast_recovery: {
      default: true,
      description: "Enable automatic recovery of failed broadcasts",
      rollout_percentage: 100,
      circuit_breaker: true,
      fallback_method: :manual_recovery_only
    },

    # Batch progress collection
    progress_batch_collection: {
      default: true,
      description: "Enable batched progress updates to reduce broadcast overhead",
      rollout_percentage: 100,
      circuit_breaker: true,
      fallback_method: :individual_progress_updates
    },

    # Dead letter queue
    dead_letter_queue: {
      default: true,
      description: "Enable dead letter queue for failed broadcasts",
      rollout_percentage: 100,
      circuit_breaker: false,
      fallback_method: :log_only_failures
    },

    # Priority-based broadcasting
    priority_broadcasting: {
      default: true,
      description: "Enable priority-based broadcasting with different retry strategies",
      rollout_percentage: 100,
      circuit_breaker: false,
      fallback_method: :single_priority_broadcasting
    }
  }.freeze

  # Circuit breaker states
  CIRCUIT_BREAKER_STATES = {
    closed: "closed",     # Normal operation
    open: "open",         # Feature disabled due to errors
    half_open: "half_open" # Testing if feature has recovered
  }.freeze

  # Circuit breaker configuration
  CIRCUIT_BREAKER_CONFIG = {
    failure_threshold: 5,        # Number of failures before opening
    success_threshold: 3,        # Number of successes before closing
    timeout: 60.seconds,         # How long to keep circuit open
    monitoring_window: 300.seconds # Window for tracking failures
  }.freeze

  class << self
    # Check if a feature is enabled globally
    # @param feature [Symbol] Feature name
    # @return [Boolean] True if enabled
    def enabled?(feature)
      return false unless FEATURES.key?(feature)

      config = FEATURES[feature]

      # Check environment variable override
      env_key = "BROADCAST_FEATURE_#{feature.to_s.upcase}"
      return parse_boolean(ENV[env_key]) if ENV.key?(env_key)

      # Check circuit breaker status
      return false if circuit_breaker_open?(feature)

      # Check default configuration
      config[:default]
    end

    # Check if a feature is enabled for a specific user
    # @param feature [Symbol] Feature name
    # @param user_id [Integer, String] User identifier
    # @return [Boolean] True if enabled for user
    def enabled_for_user?(feature, user_id:)
      return false unless FEATURES.key?(feature)

      # Check if globally enabled first
      return true if enabled?(feature)

      config = FEATURES[feature]
      rollout_percentage = config[:rollout_percentage]

      return false if rollout_percentage <= 0
      return true if rollout_percentage >= 100

      # Use consistent hashing for user-based rollout
      user_hash = Digest::MD5.hexdigest("#{feature}_#{user_id}")[0, 8].to_i(16)
      user_percentage = (user_hash % 100) + 1

      user_percentage <= rollout_percentage
    end

    # Check if a feature is enabled for a specific session
    # @param feature [Symbol] Feature name
    # @param session_id [String] Session identifier
    # @return [Boolean] True if enabled for session
    def enabled_for_session?(feature, session_id:)
      enabled_for_user?(feature, user_id: session_id)
    end

    # Execute code with feature flag check and fallback
    # @param feature [Symbol] Feature name
    # @param user_id [Integer, String] Optional user ID for user-specific checks
    # @param session_id [String] Optional session ID for session-specific checks
    # @yield Block to execute if feature is enabled
    # @return [Object] Result of block or fallback
    def with_feature(feature, user_id: nil, session_id: nil, &block)
      feature_enabled = if user_id
        enabled_for_user?(feature, user_id: user_id)
      elsif session_id
        enabled_for_session?(feature, session_id: session_id)
      else
        enabled?(feature)
      end

      if feature_enabled
        begin
          result = block.call
          record_feature_success(feature)
          result
        rescue StandardError => e
          record_feature_failure(feature, e)
          execute_fallback(feature, e)
        end
      else
        execute_fallback(feature, nil)
      end
    end

    # Execute code with fallback on feature failure
    # @param feature [Symbol] Feature name
    # @yield Block to execute
    # @return [Object] Result of block or fallback
    def with_fallback(feature, &block)
      return block.call unless FEATURES.key?(feature)

      begin
        result = block.call
        record_feature_success(feature)
        result
      rescue StandardError => e
        Rails.logger.warn "[FEATURE_FLAGS] Feature #{feature} failed: #{e.message}"
        record_feature_failure(feature, e)
        execute_fallback(feature, e)
      end
    end

    # Get feature configuration
    # @param feature [Symbol] Feature name
    # @return [Hash] Feature configuration
    def feature_config(feature)
      FEATURES[feature] || {}
    end

    # Get all feature statuses
    # @param user_id [Integer, String] Optional user ID for user-specific status
    # @return [Hash] Feature statuses
    def all_feature_status(user_id: nil)
      FEATURES.keys.map do |feature|
        status = if user_id
          enabled_for_user?(feature, user_id: user_id)
        else
          enabled?(feature)
        end

        [ feature, {
          enabled: status,
          config: FEATURES[feature],
          circuit_breaker_state: get_circuit_breaker_state(feature),
          usage_stats: get_feature_usage_stats(feature)
        } ]
      end.to_h
    end

    # Manually open circuit breaker for a feature
    # @param feature [Symbol] Feature name
    # @param reason [String] Reason for opening circuit
    def open_circuit_breaker!(feature, reason: "Manual intervention")
      return unless FEATURES.key?(feature) && FEATURES[feature][:circuit_breaker]

      cache_key = "circuit_breaker:#{feature}"
      circuit_data = {
        state: CIRCUIT_BREAKER_STATES[:open],
        opened_at: Time.current.to_i,
        reason: reason,
        failure_count: CIRCUIT_BREAKER_CONFIG[:failure_threshold]
      }

      Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)

      Rails.logger.warn "[FEATURE_FLAGS] Circuit breaker opened for #{feature}: #{reason}"
    end

    # Manually close circuit breaker for a feature
    # @param feature [Symbol] Feature name
    def close_circuit_breaker!(feature)
      return unless FEATURES.key?(feature) && FEATURES[feature][:circuit_breaker]

      cache_key = "circuit_breaker:#{feature}"
      Rails.cache.delete(cache_key)

      Rails.logger.info "[FEATURE_FLAGS] Circuit breaker closed for #{feature}"
    end

    # Get feature usage analytics
    # @param feature [Symbol] Feature name
    # @return [Hash] Usage statistics
    def get_feature_usage_stats(feature)
      # This would integrate with the analytics system
      {
        total_uses: 0,
        success_rate: 100.0,
        avg_response_time: 0.0,
        last_used: nil
      }
    end

    private

    # Check if circuit breaker is open for a feature
    # @param feature [Symbol] Feature name
    # @return [Boolean] True if circuit is open
    def circuit_breaker_open?(feature)
      config = FEATURES[feature]
      return false unless config[:circuit_breaker]

      cache_key = "circuit_breaker:#{feature}"
      circuit_data = Rails.cache.read(cache_key)

      return false unless circuit_data

      case circuit_data[:state]
      when CIRCUIT_BREAKER_STATES[:open]
        # Check if timeout has elapsed
        if Time.current.to_i - circuit_data[:opened_at] > CIRCUIT_BREAKER_CONFIG[:timeout]
          # Move to half-open state
          circuit_data[:state] = CIRCUIT_BREAKER_STATES[:half_open]
          Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)
          false
        else
          true
        end
      when CIRCUIT_BREAKER_STATES[:half_open]
        false # Allow limited testing
      else
        false
      end
    end

    # Get current circuit breaker state
    # @param feature [Symbol] Feature name
    # @return [String] Circuit breaker state
    def get_circuit_breaker_state(feature)
      config = FEATURES[feature]
      return "disabled" unless config[:circuit_breaker]

      cache_key = "circuit_breaker:#{feature}"
      circuit_data = Rails.cache.read(cache_key)

      return CIRCUIT_BREAKER_STATES[:closed] unless circuit_data

      circuit_data[:state] || CIRCUIT_BREAKER_STATES[:closed]
    end

    # Record successful feature usage
    # @param feature [Symbol] Feature name
    def record_feature_success(feature)
      config = FEATURES[feature]
      return unless config[:circuit_breaker]

      cache_key = "circuit_breaker:#{feature}"
      circuit_data = Rails.cache.read(cache_key) || {}

      if circuit_data[:state] == CIRCUIT_BREAKER_STATES[:half_open]
        success_count = (circuit_data[:success_count] || 0) + 1

        if success_count >= CIRCUIT_BREAKER_CONFIG[:success_threshold]
          # Close the circuit
          Rails.cache.delete(cache_key)
          Rails.logger.info "[FEATURE_FLAGS] Circuit breaker closed for #{feature} after #{success_count} successes"
        else
          circuit_data[:success_count] = success_count
          Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)
        end
      end

      # Record usage analytics
      record_feature_analytics(feature, :success)
    end

    # Record failed feature usage
    # @param feature [Symbol] Feature name
    # @param error [StandardError] Error that occurred
    def record_feature_failure(feature, error)
      config = FEATURES[feature]
      return unless config[:circuit_breaker]

      cache_key = "circuit_breaker:#{feature}"
      circuit_data = Rails.cache.read(cache_key) || { failure_count: 0 }

      failure_count = circuit_data[:failure_count] + 1

      if failure_count >= CIRCUIT_BREAKER_CONFIG[:failure_threshold]
        # Open the circuit
        circuit_data.merge!(
          state: CIRCUIT_BREAKER_STATES[:open],
          opened_at: Time.current.to_i,
          reason: "Failure threshold exceeded: #{error.message}",
          failure_count: failure_count
        )

        Rails.logger.error "[FEATURE_FLAGS] Circuit breaker opened for #{feature} after #{failure_count} failures: #{error.message}"
      else
        circuit_data[:failure_count] = failure_count
      end

      Rails.cache.write(cache_key, circuit_data, expires_in: 1.hour)

      # Record failure analytics
      record_feature_analytics(feature, :failure, error: error.message)
    end

    # Execute fallback for a feature
    # @param feature [Symbol] Feature name
    # @param error [StandardError, nil] Error that triggered fallback
    # @return [Object] Fallback result
    def execute_fallback(feature, error)
      config = FEATURES[feature]
      fallback_method = config[:fallback_method]

      return nil unless fallback_method

      Rails.logger.info "[FEATURE_FLAGS] Executing fallback #{fallback_method} for #{feature}" + (error ? " due to error: #{error.message}" : "")

      case fallback_method
      when :rails_cache_analytics
        # Use Rails cache instead of Redis
        BroadcastAnalytics.get_metrics
      when :basic_rate_limiting
        # Use simple rate limiting instead of enhanced
        true # Always allow for now
      when :skip_validation
        # Skip validation entirely
        true
      when :manual_recovery_only
        # Don't attempt automatic recovery
        false
      when :individual_progress_updates
        # Send individual updates instead of batched
        true
      when :log_only_failures
        # Just log failures instead of storing them
        Rails.logger.error "[FALLBACK] Broadcast failed: #{error&.message}"
        false
      when :single_priority_broadcasting
        # Use single priority instead of multiple priorities
        true
      else
        Rails.logger.warn "[FEATURE_FLAGS] Unknown fallback method: #{fallback_method}"
        nil
      end
    end

    # Record feature usage analytics
    # @param feature [Symbol] Feature name
    # @param result [Symbol] :success or :failure
    # @param error [String] Error message if failed
    def record_feature_analytics(feature, result, error: nil)
      begin
        RedisAnalyticsService.increment_counter(
          "feature_usage",
          tags: {
            feature: feature.to_s,
            result: result.to_s,
            error_type: error ? error.split(":").first : nil
          }
        )
      rescue StandardError => e
        Rails.logger.debug "[FEATURE_FLAGS] Failed to record analytics: #{e.message}"
      end
    end

    # Parse boolean from string
    # @param value [String] String value
    # @return [Boolean] Boolean value
    def parse_boolean(value)
      %w[true 1 yes on enabled].include?(value.to_s.downcase)
    end
  end
end
end
