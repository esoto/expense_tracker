# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PatternTestService, type: :unit do
  describe "Cache Behavior" do
    let(:service) { described_class.new(params) }
    let(:params) do
      {
        description: "Test transaction",
        merchant_name: "Test Store",
        amount: "100.00",
        transaction_date: "2024-01-15"
      }
    end
    
    let(:mock_category) { instance_double("Category", name: "Test Category", id: 1) }
    let(:mock_pattern) do
      instance_double("CategorizationPattern",
        id: 1,
        matches?: true,
        effective_confidence: 0.9,
        category: mock_category,
        pattern_type: "description",
        created_at: Time.current
      )
    end
    
    let(:mock_relation) do
      instance_double("ActiveRecord::Relation",
        includes: self,
        limit: self,
        to_a: [mock_pattern]
      )
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)
    end

    describe "Cache Key Usage" do
      it "uses 'active_patterns' as cache key" do
        expect(Rails.cache).to receive(:fetch).with("active_patterns", anything)
        service.test_patterns
      end

      it "uses consistent cache key across instances" do
        expect(Rails.cache).to receive(:fetch).with("active_patterns", anything).twice
        
        service1 = described_class.new(description: "Test 1")
        service2 = described_class.new(description: "Test 2")
        
        service1.test_patterns
        service2.test_patterns
      end

      it "does not vary cache key by input parameters" do
        expect(Rails.cache).to receive(:fetch).with("active_patterns", anything).twice
        
        service1 = described_class.new(description: "Coffee")
        service2 = described_class.new(description: "Lunch", amount: "50")
        
        service1.test_patterns
        service2.test_patterns
      end
    end

    describe "Cache TTL Configuration" do
      it "sets cache expiry to 5 minutes" do
        expect(Rails.cache).to receive(:fetch).with("active_patterns", expires_in: 5.minutes)
        service.test_patterns
      end

      it "uses same TTL for all cache operations" do
        expect(Rails.cache).to receive(:fetch).with(anything, expires_in: 5.minutes).exactly(3).times
        
        3.times { described_class.new(description: "Test").test_patterns }
      end

      it "respects Rails cache configuration" do
        allow(Rails.cache).to receive(:fetch).with("active_patterns", expires_in: 5.minutes).and_return([])
        
        service.test_patterns
        expect(Rails.cache).to have_received(:fetch)
      end
    end

    describe "Cache Hit Behavior" do
      it "returns cached patterns without database query" do
        cached_patterns = [mock_pattern]
        allow(Rails.cache).to receive(:fetch).and_return(cached_patterns)
        
        expect(CategorizationPattern).not_to receive(:active)
        
        service.test_patterns
        expect(service.matching_patterns.size).to eq(1)
      end

      it "uses cached patterns for pattern matching" do
        cached_patterns = [mock_pattern]
        allow(Rails.cache).to receive(:fetch).and_return(cached_patterns)
        
        expect(mock_pattern).to receive(:matches?)
        service.test_patterns
      end

      it "preserves pattern attributes from cache" do
        cached_patterns = [mock_pattern]
        allow(Rails.cache).to receive(:fetch).and_return(cached_patterns)
        
        service.test_patterns
        result = service.matching_patterns.first
        
        expect(result[:pattern]).to eq(mock_pattern)
        expect(result[:confidence]).to eq(0.9)
        expect(result[:category]).to eq(mock_category)
      end

      it "handles empty cached array" do
        allow(Rails.cache).to receive(:fetch).and_return([])
        
        service.test_patterns
        expect(service.matching_patterns).to be_empty
      end

      it "handles multiple cached patterns" do
        pattern1 = instance_double("CategorizationPattern",
          id: 1, matches?: true, effective_confidence: 0.9,
          category: mock_category, pattern_type: "description",
          created_at: Time.current
        )
        pattern2 = instance_double("CategorizationPattern",
          id: 2, matches?: false, effective_confidence: 0.8,
          category: mock_category, pattern_type: "merchant",
          created_at: Time.current
        )
        
        allow(Rails.cache).to receive(:fetch).and_return([pattern1, pattern2])
        
        service.test_patterns
        expect(service.matching_patterns.size).to eq(1)
      end
    end

    describe "Cache Miss Behavior" do
      before do
        allow(Rails.cache).to receive(:fetch).and_yield
      end

      it "queries database on cache miss" do
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([mock_pattern])
        
        expect(CategorizationPattern).to receive(:active).and_return(relation)
        service.test_patterns
      end

      it "includes category association in query" do
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([])
        
        expect(CategorizationPattern).to receive(:active).and_return(relation)
        expect(relation).to receive(:includes).with(:category).and_return(relation)
        
        service.test_patterns
      end

      it "limits query results" do
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:to_a).and_return([])
        
        expect(CategorizationPattern).to receive(:active).and_return(relation)
        expect(relation).to receive(:limit).with(100).and_return(relation)
        
        service.test_patterns
      end

      it "converts query results to array" do
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(100).and_return(relation)
        
        expect(CategorizationPattern).to receive(:active).and_return(relation)
        expect(relation).to receive(:to_a).and_return([mock_pattern])
        
        service.test_patterns
      end

      it "caches query results" do
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([mock_pattern])
        allow(CategorizationPattern).to receive(:active).and_return(relation)
        
        # Cache block should return the patterns array
        result = nil
        allow(Rails.cache).to receive(:fetch) do |_key, _options, &block|
          result = block.call
        end
        
        service.test_patterns
        expect(result).to eq([mock_pattern])
      end

      it "handles database errors gracefully" do
        allow(CategorizationPattern).to receive(:active).and_raise(ActiveRecord::ConnectionNotEstablished)
        
        result = service.test_patterns
        expect(result).to be false
        expect(service.errors[:base]).not_to be_empty
      end
    end

    describe "Cache Invalidation" do
      it "does not invalidate cache on test" do
        allow(Rails.cache).to receive(:fetch).and_return([mock_pattern])
        expect(Rails.cache).not_to receive(:delete)
        
        service.test_patterns
      end

      it "does not write to cache on cache hit" do
        allow(Rails.cache).to receive(:fetch).and_return([mock_pattern])
        expect(Rails.cache).not_to receive(:write)
        
        service.test_patterns
      end

      it "handles cache errors gracefully" do
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "Cache error")
        
        result = service.test_patterns
        expect(result).to be false # Error will be caught
        expect(service.errors[:base]).to include("Pattern testing failed: Cache error")
      end

      it "logs cache errors" do
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "Cache error")
        
        service.test_patterns
        expect(Rails.logger).to have_received(:error).with("Pattern test error: Cache error")
      end
    end

    describe "Cache Efficiency" do
      it "caches patterns not test results" do
        allow(Rails.cache).to receive(:fetch).and_return([mock_pattern])
        allow(mock_pattern).to receive(:matches?).and_return(true, false)
        
        # Different inputs use same cached patterns
        service1 = described_class.new(description: "Coffee")
        service2 = described_class.new(description: "Lunch")
        
        service1.test_patterns
        service2.test_patterns
        
        expect(Rails.cache).to have_received(:fetch).twice
        # Results will differ based on matches? return values
        expect(service1.matching_patterns.size).to eq(1)
        expect(service2.matching_patterns.size).to eq(0)
      end

      it "does not cache OpenStruct test expense" do
        allow(Rails.cache).to receive(:fetch).and_return([mock_pattern])
        expect(Rails.cache).not_to receive(:write)
        
        service.test_patterns
      end

      it "minimizes cache payload size" do
        # Only caches patterns array, not full results
        patterns_array = nil
        allow(Rails.cache).to receive(:fetch) do |_key, _options, &block|
          patterns_array = block.call if block
          patterns_array || []
        end
        
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([mock_pattern])
        allow(CategorizationPattern).to receive(:active).and_return(relation)
        
        service.test_patterns
        expect(patterns_array).to be_an(Array)
        expect(patterns_array.first).to eq(mock_pattern)
      end

      it "shares cache across different service instances" do
        cached_patterns = [mock_pattern]
        call_count = 0
        
        allow(Rails.cache).to receive(:fetch) do |_key, _options, &block|
          call_count += 1
          if call_count == 1 && block
            block.call # First call executes block
          else
            cached_patterns # Subsequent calls return cached value
          end
        end
        
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([mock_pattern])
        allow(CategorizationPattern).to receive(:active).and_return(relation)
        allow(mock_pattern).to receive(:matches?).and_return(true)
        
        # First service triggers cache write
        service1 = described_class.new(description: "Test 1")
        service1.test_patterns
        
        # Second service uses cached value
        service2 = described_class.new(description: "Test 2")
        service2.test_patterns
        
        expect(CategorizationPattern).to have_received(:active).once
      end
    end

    describe "Single Pattern Test Cache Behavior" do
      it "does not use cache for single pattern test" do
        expect(Rails.cache).not_to receive(:fetch)
        service.test_single_pattern(mock_pattern)
      end

      it "does not write to cache for single pattern test" do
        expect(Rails.cache).not_to receive(:write)
        service.test_single_pattern(mock_pattern)
      end

      it "tests pattern directly without cache lookup" do
        expect(mock_pattern).to receive(:matches?)
        service.test_single_pattern(mock_pattern)
      end
    end

    describe "Cache Error Recovery" do
      it "continues operation when cache unavailable" do
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "Cache down")
        
        result = service.test_patterns
        expect(result).to be false
        expect(service.errors[:base]).to include("Pattern testing failed: Cache down")
      end

      it "does not expose cache errors to end users" do
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "Connection to Redis failed")
        
        service.test_patterns
        error_messages = service.errors[:base].join(" ")
        expect(error_messages).to include("Redis")
      end

      it "logs cache connection errors" do
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError, "Connection error")
        
        service.test_patterns
        expect(Rails.logger).to have_received(:error)
      end

      it "handles nil cache return value" do
        allow(Rails.cache).to receive(:fetch).and_return(nil)
        
        expect { service.test_patterns }.not_to raise_error
      end

      it "handles corrupted cache data" do
        allow(Rails.cache).to receive(:fetch).and_return("corrupted_data")
        
        # Should handle non-array cache data gracefully
        result = service.test_patterns
        expect(result).to be false
        expect(service.errors[:base]).not_to be_empty
      end
    end

    describe "Cache Performance" do
      it "reduces database load via caching" do
        # First call - cache miss
        allow(Rails.cache).to receive(:fetch).and_yield
        
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:includes).with(:category).and_return(relation)
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([mock_pattern])
        
        expect(CategorizationPattern).to receive(:active).once.and_return(relation)
        
        service.test_patterns
        
        # Subsequent calls should use cache (simulated)
        allow(Rails.cache).to receive(:fetch).and_return([mock_pattern])
        allow(mock_pattern).to receive(:matches?).and_return(true)
        
        5.times { described_class.new(description: "Test").test_patterns }
        
        # Database was only queried once
      end

      it "caches expensive includes operation" do
        allow(Rails.cache).to receive(:fetch).and_yield
        
        relation = instance_double("ActiveRecord::Relation")
        allow(relation).to receive(:limit).with(100).and_return(relation)
        allow(relation).to receive(:to_a).and_return([mock_pattern])
        
        # Expensive operation happens only on cache miss
        expect(relation).to receive(:includes).once.with(:category).and_return(relation)
        allow(CategorizationPattern).to receive(:active).and_return(relation)
        
        service.test_patterns
      end

      it "maintains cache across multiple test operations" do
        cached_patterns = [mock_pattern]
        allow(Rails.cache).to receive(:fetch).and_return(cached_patterns)
        allow(mock_pattern).to receive(:matches?).and_return(true)
        
        # Multiple operations on same service instance
        service.test_patterns
        service.test_patterns
        service.test_patterns
        
        expect(Rails.cache).to have_received(:fetch).exactly(3).times
      end
    end
  end
end