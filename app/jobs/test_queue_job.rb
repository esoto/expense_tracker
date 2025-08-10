# frozen_string_literal: true

# Test job for queue visualization demonstration
class TestQueueJob < ApplicationJob
  queue_as :default

  def perform(message = "Test job executed")
    Rails.logger.info "TestQueueJob: #{message}"
    sleep 2 # Simulate some work
    Rails.logger.info "TestQueueJob: Completed"
  end
end