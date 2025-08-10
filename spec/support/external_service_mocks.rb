# frozen_string_literal: true

# Conservative mocks for external services
# Tests must explicitly opt-in to use these mocks
module ExternalServiceMocks
  # Stub ActionCable broadcasts when needed
  def stub_action_cable_for_tests
    return unless defined?(ActionCable)

    allow(ActionCable.server).to receive(:broadcast).and_return(true)
  end

  # Stub specific channel broadcasts
  def stub_sync_status_channel
    return unless defined?(SyncStatusChannel)

    # Only stub methods that actually exist
    if SyncStatusChannel.respond_to?(:broadcast_to)
      allow(SyncStatusChannel).to receive(:broadcast_to).and_return(true)
    end

    if SyncStatusChannel.respond_to?(:broadcast_progress)
      allow(SyncStatusChannel).to receive(:broadcast_progress).and_return(true)
    end

    if SyncStatusChannel.respond_to?(:broadcast_activity)
      allow(SyncStatusChannel).to receive(:broadcast_activity).and_return(true)
    end

    if SyncStatusChannel.respond_to?(:broadcast_error)
      allow(SyncStatusChannel).to receive(:broadcast_error).and_return(true)
    end

    if SyncStatusChannel.respond_to?(:broadcast_completion)
      allow(SyncStatusChannel).to receive(:broadcast_completion).and_return(true)
    end
  end

  # Stub broadcast reliability service when needed
  def stub_broadcast_reliability_service
    return unless defined?(BroadcastReliabilityService)

    allow(BroadcastReliabilityService).to receive(:broadcast_with_retry).and_return(true)
    allow(BroadcastReliabilityService).to receive(:ensure_delivery).and_return(true)
  end

  # Configure ActionMailer for tests
  def stub_action_mailer_for_tests
    return unless defined?(ActionMailer)

    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = false
  end

  # Convenience method to stub all external services
  def stub_all_external_services
    stub_action_cable_for_tests
    stub_broadcast_reliability_service
    stub_action_mailer_for_tests
  end
end

RSpec.configure do |config|
  config.include ExternalServiceMocks

  # Only stub when tests explicitly request it via metadata
  config.before(:each, :stub_broadcasts) do
    stub_action_cable_for_tests
    stub_broadcast_reliability_service
  end

  config.before(:each, :stub_action_cable) do
    stub_action_cable_for_tests
  end

  config.before(:each, :stub_external_services) do
    stub_all_external_services
  end
end
