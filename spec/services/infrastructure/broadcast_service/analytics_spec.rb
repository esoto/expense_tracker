# frozen_string_literal: true

require 'rails_helper'
require 'support/broadcast_service_test_helper'

RSpec.describe Infrastructure::BroadcastService::Analytics, :unit do
  include BroadcastServiceTestHelper
  
  before(:each) do
    setup_minimal_test_environment
  end
  
  after(:each) do
    teardown_minimal_test_environment
  end
  
  let(:channel) { 'TestChannel' }
  let(:target) { create_test_target(id: 1) }
  
  describe '.record' do
    context 'successful broadcasts' do
      let(:result) { { success: true, duration: 0.125 } }
      
      it 'increments success count' do
        freeze_time do
          described_class.record(channel, target, :medium, result)
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:success_count]).to eq(1)
          expect(metrics[:failure_count]).to eq(0)
        end
      end
      
      it 'accumulates total duration' do
        freeze_time do
          described_class.record(channel, target, :medium, result)
          described_class.record(channel, target, :medium, { success: true, duration: 0.250 })
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:total_duration]).to eq(0.375)
        end
      end
      
      it 'tracks metrics by priority' do
        freeze_time do
          described_class.record(channel, target, :high, result)
          described_class.record(channel, target, :medium, { success: true, duration: 0.200 })
          described_class.record(channel, target, :low, { success: true, duration: 0.300 })
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:by_priority][:high][:count]).to eq(1)
          expect(metrics[:by_priority][:high][:duration]).to eq(0.125)
          expect(metrics[:by_priority][:medium][:count]).to eq(1)
          expect(metrics[:by_priority][:medium][:duration]).to eq(0.200)
          expect(metrics[:by_priority][:low][:count]).to eq(1)
          expect(metrics[:by_priority][:low][:duration]).to eq(0.300)
        end
      end
    end
    
    context 'failed broadcasts' do
      let(:result) { { success: false, error: "Test error" } }
      
      it 'increments failure count' do
        freeze_time do
          described_class.record(channel, target, :medium, result)
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:failure_count]).to eq(1)
          expect(metrics[:success_count]).to eq(0)
        end
      end
      
      it 'does not accumulate duration for failures' do
        freeze_time do
          described_class.record(channel, target, :medium, result)
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:total_duration]).to eq(0)
        end
      end
      
      it 'tracks failure count by priority' do
        freeze_time do
          described_class.record(channel, target, :high, result)
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:by_priority][:high][:count]).to eq(1)
          expect(metrics[:by_priority][:high][:duration]).to eq(0)
        end
      end
    end
    
    context 'cache expiration' do
      it 'sets 24-hour expiration for metrics' do
        freeze_time do
          described_class.record(channel, target, :medium, { success: true, duration: 0.1 })
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          
          # Verify data exists
          expect(Rails.cache.read(key)).not_to be_nil
          
          # Travel past expiration
          travel 25.hours
          expect(Rails.cache.read(key)).to be_nil
        end
      end
    end
    
    context 'concurrent recording' do
      it 'handles concurrent metric updates' do
        freeze_time do
          threads = []
          
          10.times do |i|
            threads << Thread.new do
              described_class.record(channel, target, :medium, { success: true, duration: 0.1 * i })
            end
          end
          
          threads.each(&:join)
          
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          metrics = Rails.cache.read(key)
          
          expect(metrics[:success_count]).to eq(10)
          expect(metrics[:total_duration]).to be_within(0.01).of(4.5) # Sum of 0.0 to 0.9
        end
      end
    end
  end
  
  describe '.get_metrics' do
    context 'basic metrics aggregation' do
      before do
        # Clear cache before each test in this context
        Rails.cache.clear
        
        freeze_time do
          # Record some test metrics
          described_class.record('Channel1', target, :high, { success: true, duration: 0.1 })
          described_class.record('Channel1', target, :medium, { success: true, duration: 0.2 })
          described_class.record('Channel2', target, :low, { success: false })
          described_class.record('Channel2', target, :high, { success: true, duration: 0.3 })
        end
      end
      
      it 'aggregates total broadcasts' do
        freeze_time do
          metrics = described_class.get_metrics(time_window: 1.hour)
          
          expect(metrics[:total_broadcasts]).to eq(4)
          expect(metrics[:success_count]).to eq(3)
          expect(metrics[:failure_count]).to eq(1)
        end
      end
      
      it 'calculates success rate' do
        freeze_time do
          metrics = described_class.get_metrics(time_window: 1.hour)
          
          expect(metrics[:success_rate]).to eq(75.0)
        end
      end
      
      it 'calculates average duration' do
        freeze_time do
          metrics = described_class.get_metrics(time_window: 1.hour)
          
          # (0.1 + 0.2 + 0.3) / 3 = 0.2
          expect(metrics[:average_duration]).to be_within(0.01).of(0.2)
        end
      end
      
      it 'aggregates by channel' do
        freeze_time do
          metrics = described_class.get_metrics(time_window: 1.hour)
          
          expect(metrics[:by_channel]['Channel1'][:count]).to eq(2)
          expect(metrics[:by_channel]['Channel1'][:duration]).to be_within(0.001).of(0.3)
          expect(metrics[:by_channel]['Channel2'][:count]).to eq(1)
          expect(metrics[:by_channel]['Channel2'][:duration]).to be_within(0.001).of(0.3)
        end
      end
      
      it 'aggregates by priority' do
        freeze_time do
          metrics = described_class.get_metrics(time_window: 1.hour)
          
          expect(metrics[:by_priority][:high][:count]).to eq(2)
          expect(metrics[:by_priority][:high][:duration]).to eq(0.4)
          expect(metrics[:by_priority][:medium][:count]).to eq(1)
          expect(metrics[:by_priority][:medium][:duration]).to eq(0.2)
          expect(metrics[:by_priority][:low][:count]).to eq(1)
        end
      end
    end
    
    context 'time window filtering' do
      it 'respects time window parameter' do
        # Clear cache to ensure test isolation
        Rails.cache.clear
        
        current = Time.current.beginning_of_day + 12.hours # Noon today
        
        # Record old metric 2 days ago (different date)
        travel_to(current - 2.days) do
          described_class.record(channel, target, :medium, { success: true, duration: 0.1 })
        end
        
        # Record recent metric at current time
        travel_to(current) do
          described_class.record(channel, target, :medium, { success: true, duration: 0.2 })
          
          # Get metrics for the last day only (should not include 2-day-old metric)
          metrics = described_class.get_metrics(time_window: 1.day)
          
          # Should only include today's metric
          expect(metrics[:total_broadcasts]).to eq(1)
          expect(metrics[:success_count]).to eq(1)
        end
      end
      
      it 'handles multi-day time windows' do
        # Clear cache to ensure test isolation
        Rails.cache.clear
        
        # Since cache entries created in past travel_to blocks don't persist properly,
        # we need to create all the data in a single time context and manually set the keys
        freeze_time do
          current_date = Date.current
          
          # Manually create cache entries for multiple days
          # This simulates having recorded metrics over multiple days
          (0..3).each do |days_ago|
            date = current_date - days_ago.days
            key = "broadcast_analytics:TestChannel:#{date}"
            metrics = {
              success_count: 1,
              failure_count: 0,
              total_duration: 0.1 * (days_ago + 1),
              by_priority: {
                [:high, :medium, :low, :high][days_ago] => { 
                  count: 1, 
                  duration: 0.1 * (days_ago + 1) 
                }
              }
            }
            Rails.cache.write(key, metrics, expires_in: 24.hours)
          end
          
          # Now get metrics for the last 4 days
          metrics = described_class.get_metrics(time_window: 4.days)
          
          # Should include all 4 broadcasts
          expect(metrics[:total_broadcasts]).to eq(4)
          expect(metrics[:success_count]).to eq(4)
          expect(metrics[:by_priority].keys.sort).to eq([:high, :low, :medium])
        end
      end
    end
    
    context 'edge cases' do
      it 'handles empty metrics gracefully' do
        metrics = described_class.get_metrics(time_window: 1.hour)
        
        expect(metrics[:total_broadcasts]).to eq(0)
        expect(metrics[:success_count]).to eq(0)
        expect(metrics[:failure_count]).to eq(0)
        expect(metrics[:average_duration]).to eq(0)
        expect(metrics[:success_rate]).to eq(0)
        expect(metrics[:by_channel]).to be_empty
        expect(metrics[:by_priority]).to be_empty
      end
      
      it 'handles corrupted cache data' do
        freeze_time do
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          Rails.cache.write(key, "corrupted_data")
          
          expect {
            metrics = described_class.get_metrics(time_window: 1.hour)
            expect(metrics[:total_broadcasts]).to eq(0)
          }.not_to raise_error
        end
      end
      
      it 'handles nil values in cached metrics' do
        freeze_time do
          key = "broadcast_analytics:#{channel}:#{Date.current}"
          Rails.cache.write(key, {
            success_count: nil,
            failure_count: 1,
            total_duration: nil,
            by_priority: {}
          })
          
          metrics = described_class.get_metrics(time_window: 1.hour)
          
          expect(metrics[:total_broadcasts]).to eq(1)
          expect(metrics[:failure_count]).to eq(1)
        end
      end
    end
    
    context 'cache key patterns' do
      it 'uses consistent key format' do
        freeze_time do
          described_class.record('TestChannel', target, :medium, { success: true, duration: 0.1 })
          
          expected_key = "broadcast_analytics:TestChannel:#{Date.current}"
          expect(Rails.cache.read(expected_key)).not_to be_nil
        end
      end
      
      it 'handles special characters in channel names' do
        freeze_time do
          special_channel = "Test::Channel::Nested"
          described_class.record(special_channel, target, :medium, { success: true, duration: 0.1 })
          
          key = "broadcast_analytics:#{special_channel}:#{Date.current}"
          expect(Rails.cache.read(key)).not_to be_nil
        end
      end
    end
  end
end