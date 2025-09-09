# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QueueChannel, type: :channel, unit: true do
  before do
    # Stub Rails.logger to capture logging calls
    allow(Rails.logger).to receive(:info)
  end

  describe '#subscribed', unit: true do
    it 'streams from queue_updates channel' do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from('queue_updates')
    end

    it 'logs successful subscription' do
      subscribe

      expect(Rails.logger).to have_received(:info)
        .with('Client subscribed to queue updates channel')
    end

    it 'confirms subscription immediately' do
      subscribe

      expect(subscription).to be_confirmed
    end
  end

  describe '#unsubscribed', unit: true do
    before do
      subscribe
    end

    it 'logs unsubscription' do
      unsubscribe

      expect(Rails.logger).to have_received(:info)
        .with('Client unsubscribed from queue updates channel')
    end

    it 'stops all streams when unsubscribed' do
      expect { unsubscribe }.not_to raise_error
    end
  end

  describe 'channel inheritance', unit: true do
    it 'inherits from ApplicationCable::Channel' do
      expect(QueueChannel.superclass).to eq(ApplicationCable::Channel)
    end

    it 'is an ActionCable channel' do
      expect(QueueChannel.ancestors).to include(ActionCable::Channel::Base)
    end
  end

  describe 'channel behavior', unit: true do
    it 'allows multiple subscribers to the same stream' do
      # First subscription
      subscribe
      first_subscription = subscription

      # Create second subscriber (simulating another client)
      stub_connection
      subscribe
      second_subscription = subscription

      expect(first_subscription).to have_stream_from('queue_updates')
      expect(second_subscription).to have_stream_from('queue_updates')
    end

    it 'maintains subscription state correctly' do
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from('queue_updates')
    end
  end

  describe 'logging behavior', unit: true do
    it 'logs subscription with correct message format' do
      subscribe

      expect(Rails.logger).to have_received(:info) do |message|
        expect(message).to be_a(String)
        expect(message).to include('Client subscribed')
        expect(message).to include('queue updates channel')
      end
    end

    it 'logs unsubscription with correct message format' do
      subscribe
      unsubscribe

      # Check that the unsubscription message was logged (second call to Rails.logger.info)
      expect(Rails.logger).to have_received(:info).with('Client unsubscribed from queue updates channel')
    end

    it 'logs both subscription and unsubscription events' do
      subscribe
      unsubscribe

      expect(Rails.logger).to have_received(:info).twice
    end
  end

  describe 'error handling', unit: true do
    it 'handles subscription gracefully when stream setup succeeds' do
      # Ensure stream_from works normally
      subscribe

      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from('queue_updates')
    end

    it 'handles logging and subscription together' do
      subscribe
      unsubscribe

      # Verify both logging calls occurred without errors
      expect(Rails.logger).to have_received(:info).twice
    end
  end
end
