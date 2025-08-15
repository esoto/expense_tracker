# frozen_string_literal: true

module Infrastructure
    # BroadcastService consolidates all broadcast-related functionality including
    # analytics, error handling, rate limiting, and reliability features.
    # This replaces multiple separate broadcast services for better cohesion.
    module BroadcastService
      extend ActiveSupport::Concern

      # Main broadcast method with all integrated features
      class << self
        def broadcast(channel, target, data, priority: :medium)
          return unless enabled?
          return unless rate_limit_check(target, priority)

          result = perform_broadcast(channel, target, data, priority)
          track_analytics(channel, target, priority, result)
          result
        rescue StandardError => e
          handle_error(channel, target, data, priority, e)
        end

        def enabled?
          FeatureFlags.enabled?(:broadcasting)
        end

        private

        def perform_broadcast(channel, target, data, priority)
          start_time = Time.current

          validate_request!(channel, target, data)

          # Use reliability wrapper for critical broadcasts
          if priority == :high
            ReliabilityWrapper.execute(channel, target, data)
          else
            ActionCable.server.broadcast(
              "#{channel}_#{target.class.name.underscore}_#{target.id}",
              data
            )
          end

          { success: true, duration: Time.current - start_time }
        end

        def rate_limit_check(target, priority)
          RateLimiter.allowed?(target, priority)
        end

        def track_analytics(channel, target, priority, result)
          Analytics.record(channel, target, priority, result)
        end

        def handle_error(channel, target, data, priority, error)
          ErrorHandler.handle(channel, target, data, priority, error)
        end

        def validate_request!(channel, target, data)
          RequestValidator.validate!(channel, target, data)
        end
      end

      # Analytics module for tracking broadcast metrics
      module Analytics
        CACHE_PREFIX = "broadcast_analytics"

        class << self
          def record(channel, target, priority, result)
            key = "#{CACHE_PREFIX}:#{channel}:#{Date.current}"
            metrics = Rails.cache.fetch(key, expires_in: 24.hours) { default_metrics }

            if result[:success]
              metrics[:success_count] += 1
              metrics[:total_duration] += result[:duration]
            else
              metrics[:failure_count] += 1
            end

            metrics[:by_priority][priority] ||= { count: 0, duration: 0 }
            metrics[:by_priority][priority][:count] += 1
            metrics[:by_priority][priority][:duration] += result[:duration] if result[:success]

            Rails.cache.write(key, metrics, expires_in: 24.hours)
          end

          def get_metrics(time_window: 1.hour)
            end_time = Time.current
            start_time = end_time - time_window

            metrics = {
              total_broadcasts: 0,
              success_count: 0,
              failure_count: 0,
              average_duration: 0,
              by_channel: {},
              by_priority: {}
            }

            # Aggregate metrics from cache
            (start_time.to_date..end_time.to_date).each do |date|
              pattern = "#{CACHE_PREFIX}:*:#{date}"
              Rails.cache.fetch_multi(*Rails.cache.instance_variable_get(:@data).keys.select { |k| k.match?(pattern) }) do |key, cached|
                next unless cached

                channel = key.split(":")[1]
                metrics[:total_broadcasts] += cached[:success_count] + cached[:failure_count]
                metrics[:success_count] += cached[:success_count]
                metrics[:failure_count] += cached[:failure_count]

                metrics[:by_channel][channel] ||= { count: 0, duration: 0 }
                metrics[:by_channel][channel][:count] += cached[:success_count]
                metrics[:by_channel][channel][:duration] += cached[:total_duration]

                cached[:by_priority].each do |priority, data|
                  metrics[:by_priority][priority] ||= { count: 0, duration: 0 }
                  metrics[:by_priority][priority][:count] += data[:count]
                  metrics[:by_priority][priority][:duration] += data[:duration]
                end
              end
            end

            if metrics[:success_count] > 0
              metrics[:average_duration] = metrics[:by_channel].values.sum { |v| v[:duration] } / metrics[:success_count]
            end

            metrics[:success_rate] = metrics[:total_broadcasts] > 0 ?
              (metrics[:success_count].to_f / metrics[:total_broadcasts] * 100).round(2) : 0

            metrics
          end

          private

          def default_metrics
            {
              success_count: 0,
              failure_count: 0,
              total_duration: 0,
              by_priority: {}
            }
          end
        end
      end

      # Error handling with retry logic and circuit breaker
      module ErrorHandler
        MAX_RETRIES = 3
        CIRCUIT_BREAKER_THRESHOLD = 5
        CIRCUIT_BREAKER_TIMEOUT = 5.minutes

        class << self
          def handle(channel, target, data, priority, error)
            Rails.logger.error "Broadcast failed: #{error.message}"
            Rails.logger.error error.backtrace.join("\n")

            # Track error for circuit breaker
            track_error(channel)

            # Attempt retry for high priority broadcasts
            if priority == :high && should_retry?(channel, error)
              retry_broadcast(channel, target, data, priority)
            else
              store_failed_broadcast(channel, target, data, priority, error)
            end

            { success: false, error: error.message }
          end

          private

          def track_error(channel)
            key = "broadcast_errors:#{channel}"
            count = Rails.cache.increment(key, 1, expires_in: CIRCUIT_BREAKER_TIMEOUT)

            if count >= CIRCUIT_BREAKER_THRESHOLD
              Rails.cache.write("circuit_breaker:#{channel}", true, expires_in: CIRCUIT_BREAKER_TIMEOUT)
            end
          end

          def should_retry?(channel, error)
            return false if circuit_open?(channel)
            return false if permanent_failure?(error)
            true
          end

          def circuit_open?(channel)
            Rails.cache.read("circuit_breaker:#{channel}") == true
          end

          def permanent_failure?(error)
            error.is_a?(ArgumentError) || error.is_a?(NoMethodError)
          end

          def retry_broadcast(channel, target, data, priority)
            RetryJob.set(wait: exponential_backoff).perform_later(
              channel: channel,
              target: target,
              data: data,
              priority: priority
            )
          end

          def exponential_backoff(attempt = 1)
            (2**attempt + rand(0..1000) / 1000.0).seconds
          end

          def store_failed_broadcast(channel, target, data, priority, error)
            FailedBroadcast.create!(
              channel: channel,
              target_type: target.class.name,
              target_id: target.id,
              data: data,
              priority: priority,
              error_message: error.message,
              error_backtrace: error.backtrace
            )
          end
        end
      end

      # Rate limiting to prevent abuse
      module RateLimiter
        LIMITS = {
          high: { per_minute: 100, burst: 20 },
          medium: { per_minute: 60, burst: 10 },
          low: { per_minute: 30, burst: 5 }
        }.freeze

        class << self
          def allowed?(target, priority)
            return true unless enabled?

            limit = LIMITS[priority] || LIMITS[:medium]
            key = "rate_limit:#{target.class.name}:#{target.id}"

            current = Rails.cache.read(key) || 0
            return false if current >= limit[:per_minute]

            Rails.cache.write(key, current + 1, expires_in: 1.minute)
            true
          end

          def enabled?
            FeatureFlags.enabled?(:rate_limiting)
          end
        end
      end

      # Feature flags for gradual rollout
      module FeatureFlags
        FLAGS = {
          broadcasting: true,
          rate_limiting: true,
          circuit_breaker: true,
          analytics: true,
          redis_analytics: false
        }.freeze

        class << self
          def enabled?(feature)
            FLAGS[feature] != false
          end

          def enable!(feature)
            FLAGS[feature] = true
          end

          def disable!(feature)
            FLAGS[feature] = false
          end
        end
      end

      # Request validation
      module RequestValidator
        class << self
          def validate!(channel, target, data)
            raise ArgumentError, "Channel cannot be nil" if channel.nil?
            raise ArgumentError, "Target cannot be nil" if target.nil?
            raise ArgumentError, "Data cannot be nil" if data.nil?
            raise ArgumentError, "Target must have an id" unless target.respond_to?(:id)

            validate_data_size!(data)
            validate_channel_exists!(channel)
          end

          private

          def validate_data_size!(data)
            size = data.to_json.bytesize
            max_size = 64.kilobytes

            if size > max_size
              raise ArgumentError, "Data size (#{size} bytes) exceeds maximum (#{max_size} bytes)"
            end
          end

          def validate_channel_exists!(channel)
            begin
              channel.constantize
            rescue NameError
              raise ArgumentError, "Channel #{channel} does not exist"
            end
          end
        end
      end

      # Reliability wrapper for critical broadcasts
      module ReliabilityWrapper
        class << self
          def execute(channel, target, data)
            attempts = 0
            last_error = nil

            loop do
              attempts += 1

              begin
                return ActionCable.server.broadcast(
                  "#{channel}_#{target.class.name.underscore}_#{target.id}",
                  data
                )
              rescue StandardError => e
                last_error = e

                if attempts >= MAX_RETRIES
                  raise last_error
                end

                sleep exponential_backoff(attempts)
              end
            end
          end

          private

          def exponential_backoff(attempt)
            (2**attempt + rand(0..1000) / 1000.0)
          end
        end
      end

      # Background job for retries
      class RetryJob < ApplicationJob
        queue_as :default

        def perform(channel:, target:, data:, priority:)
          BroadcastService.broadcast(channel, target, data, priority: priority)
        end
      end
    end
  end
end
