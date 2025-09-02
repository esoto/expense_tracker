# frozen_string_literal: true

require 'rails_helper'
require 'support/broadcast_service_test_helper'

RSpec.describe Infrastructure::BroadcastService, unit: true do
  include BroadcastServiceTestHelper
  include ActiveJob::TestHelper

  before(:each) do
    setup_broadcast_test_environment
    clear_enqueued_jobs
    clear_performed_jobs
  end

  after(:each) do
    teardown_broadcast_test_environment
  end

  describe 'Integration Tests - Main Orchestration Flow' do
    let(:channel) { 'TestChannel' }
    let(:target) { create_test_target(id: 123) }
    let(:data) { create_test_data(size: :small) }

    context 'successful broadcast flow' do
      it 'executes the complete broadcast pipeline with medium priority' do
        result = described_class.broadcast(channel, target, data, priority: :medium)

        expect(result).to include(success: true)
        expect(result[:duration]).to be_a(Float)
        expect(@broadcast_recorder.broadcast_count).to eq(1)

        broadcast = @broadcast_recorder.last_broadcast
        expect(broadcast[:channel]).to eq("TestChannel_broadcast_service_test_helper/broadcast_test_record_123")
        expect(broadcast[:data]).to eq(data)
      end

      it 'executes high priority broadcast with reliability wrapper' do
        allow(Infrastructure::BroadcastService::ReliabilityWrapper).to receive(:execute).and_call_original

        result = described_class.broadcast(channel, target, data, priority: :high)

        expect(result).to include(success: true)
        expect(Infrastructure::BroadcastService::ReliabilityWrapper).to have_received(:execute)
          .with(channel, target, data)
      end

      it 'records analytics for successful broadcast' do
        freeze_time do
          described_class.broadcast(channel, target, data, priority: :medium)

          metrics = Infrastructure::BroadcastService::Analytics.get_metrics(time_window: 1.hour)

          expect(metrics[:total_broadcasts]).to eq(1)
          expect(metrics[:success_count]).to eq(1)
          expect(metrics[:failure_count]).to eq(0)
          expect(metrics[:success_rate]).to eq(100.0)
          expect(metrics[:by_channel][channel]).to include(count: 1)
          expect(metrics[:by_priority][:medium]).to include(count: 1)
        end
      end
    end

    context 'broadcast with rate limiting' do
      it 'respects rate limits for medium priority' do
        # Fill up rate limit
        with_rate_limit(target, 60)

        result = described_class.broadcast(channel, target, data, priority: :medium)

        expect(result).to be_nil
        expect(@broadcast_recorder.broadcast_count).to eq(0)
      end

      it 'allows burst within rate limit' do
        5.times do
          result = described_class.broadcast(channel, target, data, priority: :medium)
          expect(result).to include(success: true)
        end

        expect(@broadcast_recorder.broadcast_count).to eq(5)
      end
    end

    context 'error handling flow' do
      it 'handles broadcast errors and stores failed broadcasts' do
        allow(@broadcast_recorder).to receive(:broadcast).and_raise(StandardError, "Network error")

        expect(FailedBroadcastStore).to receive(:create!).with(
          hash_including(
            channel_name: channel,
            target_type: 'BroadcastServiceTestHelper::BroadcastTestRecord',
            target_id: 123,
            data: data,
            priority: "medium",
            error_message: "Network error"
          )
        )

        result = described_class.broadcast(channel, target, data, priority: :medium)

        expect(result).to include(success: false, error: "Network error")
      end

      it 'retries high priority broadcasts on transient errors' do
        # Mock sleep to prevent real delays during exponential backoff
        allow_any_instance_of(Object).to receive(:sleep)

        allow(@broadcast_recorder).to receive(:broadcast).and_raise(StandardError, "Temporary error")

        expect {
          described_class.broadcast(channel, target, data, priority: :high)
        }.to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
          .with(channel: channel, target: target, data: data, priority: :high)
      end

      it 'triggers circuit breaker after threshold errors' do
        # Mock sleep to prevent real delays during exponential backoff
        allow_any_instance_of(Object).to receive(:sleep)

        allow(@broadcast_recorder).to receive(:broadcast).and_raise(StandardError, "Error")

        # Trigger 5 errors to open circuit
        5.times do
          described_class.broadcast(channel, target, data, priority: :high)
        end

        # Circuit should be open
        expect(Rails.cache.read("circuit_breaker:#{channel}")).to be true

        # High priority broadcasts should not retry when circuit is open
        expect {
          described_class.broadcast(channel, target, data, priority: :high)
        }.not_to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
      end
    end

    context 'feature flag integration' do
      it 'disables broadcasting when feature flag is off' do
        with_feature_flag(:broadcasting, false) do
          result = described_class.broadcast(channel, target, data)

          expect(result).to be_nil
          expect(@broadcast_recorder.broadcast_count).to eq(0)
        end
      end

      it 'bypasses rate limiting when feature flag is off' do
        with_feature_flag(:rate_limiting, false) do
          with_rate_limit(target, 100)

          result = described_class.broadcast(channel, target, data, priority: :medium)

          expect(result).to include(success: true)
          expect(@broadcast_recorder.broadcast_count).to eq(1)
        end
      end
    end

    context 'cross-module dependencies' do
      it 'handles analytics recording failure gracefully' do
        allow(Infrastructure::BroadcastService::Analytics).to receive(:record)
          .and_raise(StandardError, "Analytics error")

        # Should handle analytics error and return error result
        result = described_class.broadcast(channel, target, data)
        expect(result).to include(success: false, error: "Analytics error")
      end

      it 'handles rate limiter failure gracefully' do
        allow(Infrastructure::BroadcastService::RateLimiter).to receive(:allowed?)
          .and_raise(StandardError, "Rate limiter error")

        # Should handle rate limiter error gracefully
        result = described_class.broadcast(channel, target, data)
        expect(result).to include(success: false, error: "Rate limiter error")
      end
    end

    context 'state machine corruption scenarios' do
      it 'handles corrupted cache state for circuit breaker' do
        Rails.cache.write("circuit_breaker:#{channel}", "corrupted_value")

        # Should treat corrupted state as closed circuit
        expect {
          described_class.broadcast(channel, target, data, priority: :high)
        }.not_to raise_error

        expect(@broadcast_recorder.broadcast_count).to eq(1)
      end

      it 'handles corrupted analytics metrics' do
        key = "broadcast_analytics:#{channel}:#{Date.current}"
        Rails.cache.write(key, "corrupted_metrics")

        # Should handle corrupted metrics gracefully
        expect {
          described_class.broadcast(channel, target, data)
          metrics = Infrastructure::BroadcastService::Analytics.get_metrics
        }.not_to raise_error
      end
    end

    context 'cache key collision scenarios' do
      it 'handles rate limit key collisions between different targets' do
        target1 = create_test_target(id: 1)
        target2 = create_test_target(id: 1) # Same ID, potential collision

        # Rate limit first target
        59.times { described_class.broadcast(channel, target1, data, priority: :medium) }

        # Second target with same ID should have independent rate limit
        result = described_class.broadcast(channel, target2, data, priority: :medium)
        expect(result).to include(success: true)
      end

      it 'handles analytics key collisions across channels' do
        channel1 = 'TestChannel1'
        channel2 = 'TestChannel2'

        freeze_time do
          result1 = described_class.broadcast(channel1, target, data)
          result2 = described_class.broadcast(channel2, target, data)

          # Both broadcasts should succeed
          expect(result1).to include(success: true)
          expect(result2).to include(success: true)

          metrics = Infrastructure::BroadcastService::Analytics.get_metrics

          # Check that both channels were recorded
          expect(metrics[:by_channel]).to have_key(channel1)
          expect(metrics[:by_channel]).to have_key(channel2)
          expect(metrics[:total_broadcasts]).to eq(2)
        end
      end
    end
  end

  describe 'RetryJob' do
    let(:channel) { 'TestChannel' }
    let(:target) { create_test_target(id: 456) }
    let(:data) { create_test_data(size: :small) }

    it 'performs broadcast with original parameters' do
      job = Infrastructure::BroadcastService::RetryJob.new

      expect(described_class).to receive(:broadcast)
        .with(channel, target, data, priority: :high)

      job.perform(channel: channel, target: target, data: data, priority: :high)
    end

    it 'executes retries with exponential backoff' do
      allow(Infrastructure::BroadcastService::ReliabilityWrapper).to receive(:execute).and_raise(StandardError.new("Temporary failure"))

      expect {
        described_class.broadcast(channel, target, data, priority: :high)
      }.to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
        .with(channel: channel, target: target, data: data, priority: :high)
    end
  end
end
