# frozen_string_literal: true

# Concern for monitoring and instrumentation of bulk operations
module BulkOperationMonitoring
  extend ActiveSupport::Concern

  included do
    around_action :instrument_action, only: [ :categorize, :preview, :auto_categorize, :undo ]
  end

  private

  def instrument_action
    action_name = params[:action]
    start_time = Time.current

    ActiveSupport::Notifications.instrument("bulk_operation.controller", {
      action: action_name,
      user_id: current_user&.id,
      params: sanitized_params
    }) do
      yield
    end

    duration = Time.current - start_time
    log_operation_metrics(action_name, duration)
  rescue StandardError => e
    log_operation_error(action_name, e)
    raise
  end

  def log_operation_metrics(action, duration)
    Rails.logger.info({
      event: "bulk_operation_completed",
      action: action,
      user_id: current_user&.id,
      duration_ms: (duration * 1000).round(2),
      expense_count: params[:expense_ids]&.size || 0,
      timestamp: Time.current.iso8601
    }.to_json)
  end

  def log_operation_error(action, error)
    Rails.logger.error({
      event: "bulk_operation_failed",
      action: action,
      user_id: current_user&.id,
      error_class: error.class.name,
      error_message: error.message,
      backtrace: error.backtrace&.first(5),
      timestamp: Time.current.iso8601
    }.to_json)
  end

  def sanitized_params
    params.except(:expense_ids).to_unsafe_h.slice(
      :category_id, :confidence_threshold, :dry_run,
      :date_from, :date_to, :merchant_filter
    )
  end
end
