# frozen_string_literal: true

# BroadcastRetryOrchestrator handles retry logic for broadcast operations.
# This service implements exponential backoff retry patterns with configurable
# priority-based retry counts and delays.
#
# This is part of the architectural refactor to separate retry concerns
# from the core broadcasting logic.
#
# Usage:
#   broadcaster = CoreBroadcastService.new(channel: ..., target: ..., data: ...)
#   orchestrator = BroadcastRetryOrchestrator.new(
#     broadcaster: broadcaster,
#     analytics: BroadcastAnalytics,
#     error_handler: BroadcastErrorHandler
#   )
#   result = orchestrator.broadcast_with_retry(priority: :medium)
#
class BroadcastRetryOrchestrator
  # Priority levels determine retry behavior
  RETRY_CONFIGS = {
    critical: { max_retries: 5, backoff_base: 0.5 },
    high: { max_retries: 4, backoff_base: 1.0 },
    medium: { max_retries: 3, backoff_base: 2.0 },
    low: { max_retries: 2, backoff_base: 4.0 }
  }.freeze

  attr_reader :broadcaster, :analytics, :error_handler

  def initialize(broadcaster:, analytics: nil, error_handler: nil)
    @broadcaster = broadcaster
    @analytics = analytics || NullAnalytics.new
    @error_handler = error_handler || NullErrorHandler.new
  end

  # Broadcast with retry logic
  # @param priority [Symbol] Priority level (:critical, :high, :medium, :low)
  # @return [Boolean] Success status
  def broadcast_with_retry(priority: :medium)
    validate_priority!(priority)
    
    config = RETRY_CONFIGS[priority]
    attempt = 1
    start_time = Time.current

    begin
      broadcaster.broadcast
      
      # Record success
      analytics.record_success(
        channel: broadcaster.channel.to_s,
        target_type: broadcaster.target.class.name,
        target_id: broadcaster.target.id,
        priority: priority,
        attempt: attempt,
        duration: (Time.current - start_time).to_f
      )
      
      true

    rescue CoreBroadcastService::BroadcastError => e
      # Record failure
      analytics.record_failure(
        channel: broadcaster.channel.to_s,
        target_type: broadcaster.target.class.name,
        target_id: broadcaster.target.id,
        priority: priority,
        attempt: attempt,
        error: e.message,
        duration: (Time.current - start_time).to_f
      )

      if attempt < config[:max_retries]
        delay = calculate_backoff_delay(config[:backoff_base], attempt)
        Rails.logger.warn "[BROADCAST_RETRY] Retrying in #{delay}s - Attempt #{attempt}/#{config[:max_retries]}: #{e.message}"
        
        sleep(delay)
        attempt += 1
        start_time = Time.current
        retry
      else
        Rails.logger.error "[BROADCAST_RETRY] Failed after #{config[:max_retries]} attempts: #{e.message}"
        error_handler.handle_final_failure(
          broadcaster.channel,
          broadcaster.target,
          broadcaster.data,
          priority,
          e
        )
        false
      end
    end
  end

  private

  # Validate priority parameter
  # @param priority [Symbol] Priority to validate
  def validate_priority!(priority)
    return if RETRY_CONFIGS.key?(priority)
    
    raise ArgumentError, "Invalid priority '#{priority}'. Valid priorities: #{RETRY_CONFIGS.keys.join(', ')}"
  end

  # Calculate exponential backoff delay with jitter
  # @param base [Float] Base delay in seconds
  # @param attempt [Integer] Current attempt number
  # @return [Float] Delay in seconds
  def calculate_backoff_delay(base, attempt)
    delay = base * (2 ** (attempt - 1))
    jitter = rand(0.0..0.5) * delay
    delay + jitter
  end

  # Null object pattern for analytics
  class NullAnalytics
    def record_success(*); end
    def record_failure(*); end
  end

  # Null object pattern for error handler
  class NullErrorHandler
    def handle_final_failure(*); end
  end
end