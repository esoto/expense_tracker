# frozen_string_literal: true

# RateLimiting concern for preventing abuse of bulk operations
# Implements per-user rate limiting with configurable limits per action
module RateLimiting
  extend ActiveSupport::Concern

  included do
    before_action :check_bulk_operation_rate_limit!, only: [ :categorize, :auto_categorize ]
    before_action :check_export_rate_limit!, only: [ :export ]
    before_action :check_suggest_rate_limit!, only: [ :suggest ]
  end

  private

  # Rate limits for different operations
  RATE_LIMITS = {
    categorize: { limit: 10, window: 1.minute },
    auto_categorize: { limit: 5, window: 1.minute },
    export: { limit: 20, window: 1.hour },
    suggest: { limit: 15, window: 1.minute }
  }.freeze

  def check_bulk_operation_rate_limit!
    return if performed?
    operation = action_name.to_sym
    check_rate_limit!(operation)
  end

  def check_export_rate_limit!
    return if performed?
    check_rate_limit!(:export)
  end

  def check_suggest_rate_limit!
    return if performed?
    check_rate_limit!(:suggest)
  end

  def check_rate_limit!(operation)
    config = RATE_LIMITS[operation]
    return unless config

    key = rate_limit_key(operation)
    current_count = Rails.cache.increment(key, 1, expires_in: config[:window])

    if current_count > config[:limit]
      Rails.logger.warn "Rate limit exceeded for user #{current_user.id}, operation: #{operation}"

      respond_to do |format|
        format.json do
          render json: {
            error: "Rate limit exceeded. Please try again later.",
            limit: config[:limit],
            window: format_window(config[:window])
          }, status: :too_many_requests
        end
        format.turbo_stream do
          render "shared/rate_limit_exceeded",
                 locals: { message: "Too many requests. Please try again later." },
                 status: :too_many_requests
        end
        format.html do
          redirect_back(fallback_location: root_path,
                       alert: "Too many requests. Please try again later.")
        end
      end
      return
    end
  end

  def rate_limit_key(operation)
    "rate_limit:bulk_operations:#{current_user.id}:#{operation}"
  end

  def format_window(window)
    if window < 1.hour
      "#{window.to_i / 60} minutes"
    else
      "#{window.to_i / 3600} hours"
    end
  end
end
