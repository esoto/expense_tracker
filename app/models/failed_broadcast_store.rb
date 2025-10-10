# frozen_string_literal: true

# FailedBroadcastStore represents a broadcast that failed and needs manual intervention
# or retry. This serves as the dead letter queue for broadcast reliability.
#
# Fields:
# - channel_name: ActionCable channel that failed
# - target_type/target_id: Object that was target of broadcast
# - data: The broadcast data payload
# - priority: Broadcast priority level
# - error_type: Category of error for filtering/reporting
# - error_message: Detailed error message
# - failed_at: When the broadcast failed
# - retry_count: Number of retry attempts
# - sidekiq_job_id: Sidekiq job ID if applicable
# - recovered_at: When the broadcast was successfully recovered
# - recovery_notes: Manual notes about recovery process
class FailedBroadcastStore < ApplicationRecord
  # Error type constants
  ERROR_TYPES = %w[
    record_not_found
    connection_timeout
    channel_error
    job_error
    job_death
    serialization_error
    validation_error
    broadcast_failed
    unknown
  ].freeze

  # Priority levels
  PRIORITIES = %w[critical high medium low].freeze

  # Callbacks
  before_validation :ensure_data_present

  # Validations
  validates :channel_name, presence: true
  validates :target_type, presence: true
  validates :target_id, presence: true, numericality: { greater_than: 0 }
  validates :priority, presence: true, inclusion: { in: PRIORITIES }
  validates :error_type, presence: true, inclusion: { in: ERROR_TYPES }
  validates :error_message, presence: true
  validates :failed_at, presence: true
  validates :retry_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :sidekiq_job_id, uniqueness: true, allow_nil: true

  # Scopes
  scope :unrecovered, -> { where(recovered_at: nil) }
  scope :recovered, -> { where.not(recovered_at: nil) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :by_channel, ->(channel) { where(channel_name: channel) }
  scope :by_error_type, ->(error_type) { where(error_type: error_type) }
  scope :recent_failures, -> { order(failed_at: :desc) }
  scope :ready_for_retry, -> { unrecovered.where("retry_count < ?", max_retry_attempts) }

  # Class methods
  class << self
    # Get maximum retry attempts based on priority
    # @param priority [String] Priority level
    # @return [Integer] Maximum retry attempts
    def max_retry_attempts(priority = "medium")
      case priority.to_s
      when "critical" then 5
      when "high" then 4
      when "medium" then 3
      when "low" then 2
      else 3
      end
    end

    # Create from broadcast job failure
    # @param job [Hash] Sidekiq job data
    # @param error [StandardError] Error that caused failure
    # @return [FailedBroadcastStore] Created record
    def create_from_job_failure!(job, error)
      args = job["args"] || []
      create!(
        channel_name: args[0],
        target_type: args[2],
        target_id: args[1],
        data: args[3] || {},
        priority: args[4] || "medium",
        error_type: classify_error(error),
        error_message: error.message,
        failed_at: Time.current,
        retry_count: job["retry_count"] || 0,
        sidekiq_job_id: job["jid"]
      )
    end

    # Classify error type based on error class
    # @param error [StandardError] Error to classify
    # @return [String] Error type
    def classify_error(error)
      case error
      when ActiveRecord::RecordNotFound
        "record_not_found"
      when Timeout::Error, Net::ReadTimeout, Net::OpenTimeout
        "connection_timeout"
      when JSON::ParserError, JSON::GeneratorError
        "serialization_error"
      when ActiveModel::ValidationError
        "validation_error"
      else
        "unknown"
      end
    end

    # Get recovery statistics
    # @param time_period [ActiveSupport::Duration] Time period for stats
    # @return [Hash] Statistics
    def recovery_stats(time_period: 24.hours)
      start_time = Time.current - time_period

      {
        total_failures: where("failed_at >= ?", start_time).count,
        recovered: where("failed_at >= ? AND recovered_at IS NOT NULL", start_time).count,
        pending_recovery: where("failed_at >= ? AND recovered_at IS NULL", start_time).count,
        by_error_type: where("failed_at >= ?", start_time)
                      .group(:error_type)
                      .count,
        by_priority: where("failed_at >= ?", start_time)
                    .group(:priority)
                    .count
      }
    end

    # Clean up old recovered records
    # @param older_than [ActiveSupport::Duration] Clean records older than this
    # @return [Integer] Number of records deleted
    def cleanup_old_records(older_than: 1.week)
      recovered.where("recovered_at < ?", Time.current - older_than).delete_all
    end
  end

  # Instance methods

  # Check if this broadcast can be retried
  # @return [Boolean] True if can retry
  def can_retry?
    recovered_at.nil? && retry_count < self.class.max_retry_attempts(priority)
  end

  # Mark as recovered
  # @param notes [String] Recovery notes
  def mark_recovered!(notes: nil)
    update!(
      recovered_at: Time.current,
      recovery_notes: notes
    )
  end

  # Attempt to retry the failed broadcast
  # @param manual [Boolean] Whether this is a manual retry
  # @return [Boolean] Success status
  def retry_broadcast!(manual: false)
    return false unless can_retry?

    begin
      # Find the target object
      target = target_type.constantize.find(target_id)

      # Increment retry count
      increment!(:retry_count)

      # Attempt the broadcast
      success = Services::BroadcastReliabilityService.broadcast_with_retry(
        channel: channel_name,
        target: target,
        data: data,
        priority: priority.to_sym
      )

      if success
        mark_recovered!(
          notes: manual ? "Manual retry successful" : "Automatic retry successful"
        )
        Rails.logger.info "[FAILED_BROADCAST] Successfully retried: #{channel_name} -> #{target_type}##{target_id}"
        true
      else
        Rails.logger.warn "[FAILED_BROADCAST] Retry failed: #{channel_name} -> #{target_type}##{target_id}"
        false
      end

    rescue ActiveRecord::RecordNotFound => e
      # Update error if target no longer exists
      update!(
        error_type: "record_not_found",
        error_message: "Target no longer exists: #{e.message}"
      )
      false

    rescue StandardError => e
      # Update with new error information
      update!(
        error_type: self.class.classify_error(e),
        error_message: e.message
      )
      Rails.logger.error "[FAILED_BROADCAST] Retry error: #{e.message}"
      false
    end
  end

  # Get target object if it exists
  # @return [ActiveRecord::Base, nil] Target object or nil
  def target_object
    target_type.constantize.find(target_id)
  rescue ActiveRecord::RecordNotFound, NameError
    nil
  end

  # Check if the target still exists
  # @return [Boolean] True if target exists
  def target_exists?
    !target_object.nil?
  end

  # Get human-readable error description
  # @return [String] Error description
  def error_description
    case error_type
    when "record_not_found"
      "Target object #{target_type}##{target_id} not found"
    when "connection_timeout"
      "Connection timeout while broadcasting"
    when "serialization_error"
      "Failed to serialize broadcast data"
    when "validation_error"
      "Validation failed during broadcast"
    else
      error_message.truncate(100)
    end
  end

  # Get age of the failure
  # @return [ActiveSupport::Duration] Age
  def age
    Time.current - failed_at
  end

  # Check if this is a stale failure that should be cleaned up
  # @return [Boolean] True if stale
  def stale?
    age > 1.week && (recovered? || retry_count >= self.class.max_retry_attempts(priority))
  end

  private

  # Check if this failure has been recovered
  # @return [Boolean] True if recovered
  def recovered?
    recovered_at.present?
  end

  # Ensure data is present (at least an empty hash)
  def ensure_data_present
    self.data ||= {}
  end
end
