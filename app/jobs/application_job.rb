class ApplicationJob < ActiveJob::Base
  # Configure default retry behavior for Sidekiq 8+ compatibility
  retry_on StandardError, wait: 10.seconds, attempts: 3

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
end
