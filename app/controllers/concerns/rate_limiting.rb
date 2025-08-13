# frozen_string_literal: true

# Rate limiting concern for controllers to prevent abuse
module RateLimiting
  extend ActiveSupport::Concern

  included do
    # Rate limit configuration
    class_attribute :rate_limits, default: {}
  end

  class_methods do
    # Define rate limit for specific actions
    def rate_limit(action, limit: 10, period: 1.minute, by: :ip)
      rate_limits[action] = { limit: limit, period: period, by: by }
      before_action -> { check_rate_limit(action) }, only: action
    end
  end

  private

  def check_rate_limit(action)
    config = self.class.rate_limits[action]
    return unless config

    key = rate_limit_key(action, config[:by])
    count = increment_rate_limit_counter(key, config[:period])

    if count > config[:limit]
      handle_rate_limit_exceeded(action, config)
    end
  end

  def rate_limit_key(action, by)
    identifier = case by
    when :ip
                   request.remote_ip
    when :user
                   current_user&.id || "anonymous"
    when :session
                   session.id.to_s
    else
                   "global"
    end

    "rate_limit:#{controller_name}:#{action}:#{identifier}"
  end

  def increment_rate_limit_counter(key, period)
    Rails.cache.increment(key, 1, expires_in: period) || 1
  end

  def handle_rate_limit_exceeded(action, config)
    log_rate_limit_violation(action, config)

    respond_to do |format|
      format.html do
        flash[:alert] = rate_limit_message(config)
        redirect_back(fallback_location: root_path)
      end
      format.json do
        render json: {
          error: "Rate limit exceeded",
          retry_after: config[:period].to_i,
          limit: config[:limit]
        }, status: :too_many_requests
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.prepend("notifications",
          partial: "shared/notification",
          locals: {
            message: rate_limit_message(config),
            type: :error
          })
      end
    end
  end

  def rate_limit_message(config)
    "Too many requests. Please wait #{config[:period].inspect} before trying again. (Limit: #{config[:limit]} requests)"
  end

  def log_rate_limit_violation(action, config)
    Rails.logger.warn(
      {
        event: "rate_limit_exceeded",
        controller: controller_name,
        action: action,
        user_id: current_user&.id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        limit: config[:limit],
        period: config[:period].to_i,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end

  # Helper to check remaining rate limit
  def rate_limit_remaining(action)
    config = self.class.rate_limits[action]
    return nil unless config

    key = rate_limit_key(action, config[:by])
    count = Rails.cache.read(key).to_i
    [ config[:limit] - count, 0 ].max
  end

  # Reset rate limit for specific action (useful for admin override)
  def reset_rate_limit(action, identifier = nil)
    config = self.class.rate_limits[action]
    return false unless config

    key = if identifier
            "rate_limit:#{controller_name}:#{action}:#{identifier}"
    else
            rate_limit_key(action, config[:by])
    end

    Rails.cache.delete(key)
    true
  end
end
