# frozen_string_literal: true

require 'rails_helper'
require 'support/broadcast_service_test_helper'

RSpec.describe Infrastructure::BroadcastService::ErrorHandler, :unit do
  include BroadcastServiceTestHelper
  include ActiveJob::TestHelper
  
  before(:each) do
    setup_broadcast_test_environment
  end
  
  after(:each) do
    teardown_broadcast_test_environment
  end
  
  let(:channel) { 'TestChannel' }
  let(:target) { create_test_target(id: 42) }
  let(:data) { create_test_data(size: :small) }
  
  describe '.handle' do
    context 'basic error handling' do
      let(:error) { StandardError.new("Test error") }
      
      it 'logs error information' do
        # Create error with backtrace
        error_with_backtrace = StandardError.new("Test error")
        error_with_backtrace.set_backtrace(["line 1", "line 2"])
        
        expect(Rails.logger).to receive(:error).with("Broadcast failed: Test error")
        expect(Rails.logger).to receive(:error).with("line 1\nline 2")
        
        result = described_class.handle(channel, target, data, :medium, error_with_backtrace)
        expect(result[:success]).to be false
      end
      
      it 'returns failure result with error message' do
        result = described_class.handle(channel, target, data, :medium, error)
        
        expect(result).to eq(success: false, error: "Test error")
      end
      
      it 'tracks error for circuit breaker' do
        described_class.handle(channel, target, data, :medium, error)
        
        error_count = Rails.cache.read("broadcast_errors:#{channel}")
        expect(error_count).to eq(1)
      end
    end
    
    context 'circuit breaker behavior' do
      let(:error) { StandardError.new("Network failure") }
      
      it 'opens circuit after threshold errors' do
        # Trigger 4 errors (below threshold)
        4.times do
          described_class.handle(channel, target, data, :high, error)
        end
        
        expect(Rails.cache.read("circuit_breaker:#{channel}")).to be_nil
        
        # 5th error opens circuit
        described_class.handle(channel, target, data, :high, error)
        
        expect(Rails.cache.read("circuit_breaker:#{channel}")).to be true
      end
      
      it 'prevents retries when circuit is open' do
        open_circuit_breaker(channel)
        
        expect {
          described_class.handle(channel, target, data, :high, error)
        }.not_to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
      end
      
      it 'stores failed broadcast when circuit is open' do
        open_circuit_breaker(channel)
        
        expect(FailedBroadcastStore).to receive(:create!).with(
          hash_including(
            channel_name: channel,
            target_type: 'BroadcastServiceTestHelper::BroadcastTestRecord',
            target_id: 42,
            priority: "high"
          )
        )
        
        described_class.handle(channel, target, data, :high, error)
      end
      
      it 'circuit breaker expires after timeout' do
        travel_to Time.current do
          trigger_circuit_breaker(channel, 5)
          expect(Rails.cache.read("circuit_breaker:#{channel}")).to be true
          
          travel 6.minutes
          expect(Rails.cache.read("circuit_breaker:#{channel}")).to be_nil
        end
      end
    end
    
    context 'retry logic' do
      let(:transient_error) { StandardError.new("Temporary failure") }
      let(:permanent_error) { ArgumentError.new("Invalid argument") }
      
      it 'retries high priority broadcasts on transient errors' do
        expect {
          described_class.handle(channel, target, data, :high, transient_error)
        }.to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
          .with(channel: channel, target: target, data: data, priority: :high)
      end
      
      it 'does not retry medium priority broadcasts' do
        expect {
          described_class.handle(channel, target, data, :medium, transient_error)
        }.not_to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
      end
      
      it 'does not retry on permanent failures' do
        expect {
          described_class.handle(channel, target, data, :high, permanent_error)
        }.not_to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
      end
      
      it 'does not retry NoMethodError' do
        no_method_error = NoMethodError.new("undefined method")
        
        expect {
          described_class.handle(channel, target, data, :high, no_method_error)
        }.not_to have_enqueued_job(Infrastructure::BroadcastService::RetryJob)
      end
      
      it 'uses exponential backoff for retries' do
        allow(described_class).to receive(:exponential_backoff).and_call_original
        
        described_class.handle(channel, target, data, :high, transient_error)
        
        # Verify job is scheduled with delay
        expect(Infrastructure::BroadcastService::RetryJob).to have_been_enqueued
          .at(be_within(5.seconds).of(Time.current + 2.seconds))
      end
    end
    
    context 'failed broadcast storage' do
      let(:error) { StandardError.new("Storage test error") }
      
      it 'stores failed broadcast with complete details' do
        expect(FailedBroadcastStore).to receive(:create!).with(
          hash_including(
            channel_name: channel,
            target_type: 'BroadcastServiceTestHelper::BroadcastTestRecord',
            target_id: 42,
            data: data,
            priority: "low",
            error_message: "Storage test error"
          )
        )
        
        described_class.handle(channel, target, data, :low, error)
      end
      
      it 'stores failed broadcast for medium priority' do
        expect(FailedBroadcastStore).to receive(:create!)
        
        described_class.handle(channel, target, data, :medium, error)
      end
      
      it 'stores failed broadcast when retry is not possible' do
        open_circuit_breaker(channel)
        
        expect(FailedBroadcastStore).to receive(:create!)
        
        described_class.handle(channel, target, data, :high, error)
      end
    end
    
    context 'edge cases' do
      it 'handles nil error message gracefully' do
        error = StandardError.new(nil)
        
        result = described_class.handle(channel, target, data, :medium, error)
        
        expect(result[:error]).to eq("StandardError")
      end
      
      it 'handles very long error messages' do
        long_message = "Error " * 1000
        error = StandardError.new(long_message)
        
        expect {
          described_class.handle(channel, target, data, :medium, error)
        }.not_to raise_error
      end
      
      it 'handles concurrent error tracking' do
        threads = []
        error = StandardError.new("Concurrent error")
        
        10.times do
          threads << Thread.new do
            described_class.handle(channel, target, data, :medium, error)
          end
        end
        
        threads.each(&:join)
        
        error_count = Rails.cache.read("broadcast_errors:#{channel}")
        expect(error_count).to eq(10)
      end
    end
  end
end