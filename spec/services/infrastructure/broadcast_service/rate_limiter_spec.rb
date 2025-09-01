# frozen_string_literal: true

require 'rails_helper'
require 'support/broadcast_service_test_helper'

RSpec.describe Infrastructure::BroadcastService::RateLimiter, :unit do
  include BroadcastServiceTestHelper
  
  before(:each) do
    setup_broadcast_test_environment
  end
  
  after(:each) do
    teardown_broadcast_test_environment
  end
  
  let(:target) { create_test_target(id: 123) }
  
  describe '.allowed?' do
    context 'when rate limiting is enabled' do
      before do
        allow(described_class).to receive(:enabled?).and_return(true)
      end
      
      context 'high priority limits' do
        it 'allows requests within per-minute limit' do
          99.times do
            expect(described_class.allowed?(target, :high)).to be true
          end
          
          # 100th request should be allowed (at the limit)
          expect(described_class.allowed?(target, :high)).to be true
          
          # 101st request should be denied
          expect(described_class.allowed?(target, :high)).to be false
        end
        
        it 'allows burst of 20 requests' do
          20.times do
            expect(described_class.allowed?(target, :high)).to be true
          end
        end
      end
      
      context 'medium priority limits' do
        it 'allows requests within per-minute limit' do
          59.times do
            expect(described_class.allowed?(target, :medium)).to be true
          end
          
          # 60th request should be allowed (at the limit)
          expect(described_class.allowed?(target, :medium)).to be true
          
          # 61st request should be denied
          expect(described_class.allowed?(target, :medium)).to be false
        end
        
        it 'allows burst of 10 requests' do
          10.times do
            expect(described_class.allowed?(target, :medium)).to be true
          end
        end
      end
      
      context 'low priority limits' do
        it 'allows requests within per-minute limit' do
          29.times do
            expect(described_class.allowed?(target, :low)).to be true
          end
          
          # 30th request should be allowed (at the limit)
          expect(described_class.allowed?(target, :low)).to be true
          
          # 31st request should be denied
          expect(described_class.allowed?(target, :low)).to be false
        end
        
        it 'allows burst of 5 requests' do
          5.times do
            expect(described_class.allowed?(target, :low)).to be true
          end
        end
      end
      
      context 'unknown priority' do
        it 'defaults to medium priority limits' do
          60.times do
            expect(described_class.allowed?(target, :unknown)).to be true
          end
          
          expect(described_class.allowed?(target, :unknown)).to be false
        end
      end
      
      context 'rate limit expiration' do
        it 'resets counter after 1 minute' do
          # Fill up the limit
          60.times { described_class.allowed?(target, :medium) }
          expect(described_class.allowed?(target, :medium)).to be false
          
          # Travel past expiration
          travel 61.seconds do
            expect(described_class.allowed?(target, :medium)).to be true
          end
        end
        
        it 'maintains separate counters for different time windows' do
          freeze_time do
            # Fill up half the limit
            30.times { described_class.allowed?(target, :medium) }
            
            # Travel 30 seconds
            travel 30.seconds
            
            # Should still have the same count
            29.times { described_class.allowed?(target, :medium) }
            expect(described_class.allowed?(target, :medium)).to be true
            expect(described_class.allowed?(target, :medium)).to be false
          end
        end
      end
      
      context 'target isolation' do
        let(:target1) { create_test_target(id: 1) }
        let(:target2) { create_test_target(id: 2) }
        
        it 'maintains separate rate limits for different targets' do
          # Fill up limit for target1
          60.times { described_class.allowed?(target1, :medium) }
          expect(described_class.allowed?(target1, :medium)).to be false
          
          # target2 should still be allowed
          expect(described_class.allowed?(target2, :medium)).to be true
        end
        
        it 'uses target class name in rate limit key' do
          # Use the actual class name from create_test_target
          key1 = "rate_limit:#{target1.class.name}:1"
          key2 = "rate_limit:#{target2.class.name}:2"
          
          described_class.allowed?(target1, :medium)
          described_class.allowed?(target2, :medium)
          
          expect(Rails.cache.read(key1)).to eq(1)
          expect(Rails.cache.read(key2)).to eq(1)
        end
      end
      
      context 'concurrent requests' do
        it 'handles concurrent rate limit checks' do
          # Simulate concurrent requests without actual threading
          # This tests the same logic but deterministically
          allowed_count = 0
          
          # Simulate 100 concurrent requests
          100.times do
            if described_class.allowed?(target, :medium)
              allowed_count += 1
            end
          end
          
          # Should allow up to 60 requests (medium priority limit)
          expect(allowed_count).to eq(60)
          
          # Verify the counter was properly incremented
          key = "rate_limit:#{target.class.name}:123"
          expect(Rails.cache.read(key)).to eq(60)
        end
      end
    end
    
    context 'when rate limiting is disabled' do
      before do
        allow(described_class).to receive(:enabled?).and_return(false)
      end
      
      it 'allows all requests regardless of count' do
        200.times do
          expect(described_class.allowed?(target, :low)).to be true
        end
      end
      
      it 'does not increment cache counters' do
        described_class.allowed?(target, :medium)
        
        # Use the actual target class name
        key = "rate_limit:#{target.class.name}:123"
        expect(Rails.cache.read(key)).to be_nil
      end
    end
    
    context 'edge cases' do
      it 'handles nil target gracefully' do
        expect { described_class.allowed?(nil, :medium) }.not_to raise_error
        expect(described_class.allowed?(nil, :medium)).to be true # Should allow nil targets
      end
      
      it 'handles target without id gracefully' do
        target_without_id = double("Target", class: double(name: "TestModel"))
        expect { described_class.allowed?(target_without_id, :medium) }.not_to raise_error
        expect(described_class.allowed?(target_without_id, :medium)).to be true # First request should be allowed
      end
      
      it 'handles nil priority gracefully' do
        expect(described_class.allowed?(target, nil)).to be true
      end
      
      it 'handles corrupted cache values' do
        key = "rate_limit:TestModel:123"
        Rails.cache.write(key, "corrupted", expires_in: 1.minute)
        
        # Should treat corrupted value as 0 and allow request
        expect(described_class.allowed?(target, :medium)).to be true
      end
      
      it 'handles very large counter values' do
        # Use the actual target class name
        key = "rate_limit:#{target.class.name}:123"
        Rails.cache.write(key, 999999, expires_in: 1.minute)
        
        expect(described_class.allowed?(target, :medium)).to be false
      end
    end
  end
  
  describe '.enabled?' do
    it 'checks feature flag status' do
      expect(Infrastructure::BroadcastService::FeatureFlags).to receive(:enabled?)
        .with(:rate_limiting).and_return(true)
      
      expect(described_class.enabled?).to be true
    end
    
    it 'returns false when feature flag is disabled' do
      allow(Infrastructure::BroadcastService::FeatureFlags).to receive(:enabled?)
        .with(:rate_limiting).and_return(false)
      
      expect(described_class.enabled?).to be false
    end
  end
  
  describe 'LIMITS constant' do
    it 'defines limits for all priority levels' do
      expect(described_class::LIMITS).to have_key(:high)
      expect(described_class::LIMITS).to have_key(:medium)
      expect(described_class::LIMITS).to have_key(:low)
    end
    
    it 'has higher limits for higher priorities' do
      high_limit = described_class::LIMITS[:high][:per_minute]
      medium_limit = described_class::LIMITS[:medium][:per_minute]
      low_limit = described_class::LIMITS[:low][:per_minute]
      
      expect(high_limit).to be > medium_limit
      expect(medium_limit).to be > low_limit
    end
    
    it 'has burst limits for each priority' do
      described_class::LIMITS.each do |priority, limits|
        expect(limits).to have_key(:burst)
        expect(limits[:burst]).to be_a(Integer)
        expect(limits[:burst]).to be > 0
      end
    end
  end
end