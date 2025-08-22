# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuerySecurity, type: :model, unit: true do
  # Create a dummy class that includes the concern
  let(:dummy_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveSupport::Concern
      include QuerySecurity

      # Class attribute mock
      class_attribute :query_metrics, default: {}
      
      # Mock ActiveRecord methods
      def self.table_exists?
        true
      end

      def self.name
        "DummyModel"
      end

      def self.all
        MockRelation.new
      end

      def self.current_scope
        MockRelation.new
      end

      def self.where(*)
        MockRelation.new
      end

      def self.connection
        MockConnection.new
      end
      
      # Define scope method to allow defining scopes
      def self.scope(name, body)
        singleton_class.define_method(name) do |*args|
          body.call(*args)
        end
      end

      def save!(*)
        true
      end
      
      def query_security_enabled?
        false # Default to false for testing
      end

      class MockConnection
        def execute(sql)
          [{
            "QUERY PLAN" => [{
              "Plan" => {
                "Total Cost" => 500.0,
                "Plan Rows" => 100
              }
            }].to_json
          }]
        end
      end

      class MockRelation
        def to_sql
          "SELECT * FROM dummy_models"
        end

        def joins_values
          []
        end

        def left_outer_joins_values
          []
        end

        def where_clause
          Struct.new(:predicates).new([])
        end

        def where(*)
          self
        end

        def limit(*)
          self
        end
      end
    end
  end

  let(:dummy_object) { dummy_class.new }

  describe "constants" do
    it "defines MAX_QUERY_COST" do
      expect(QuerySecurity::MAX_QUERY_COST).to eq(10000)
    end

    it "defines MAX_ROWS_PER_REQUEST" do
      expect(QuerySecurity::MAX_ROWS_PER_REQUEST).to eq(1000)
    end

    it "defines RATE_LIMIT_WINDOW" do
      expect(QuerySecurity::RATE_LIMIT_WINDOW).to eq(1.minute)
    end

    it "defines MAX_REQUESTS_PER_WINDOW" do
      expect(QuerySecurity::MAX_REQUESTS_PER_WINDOW).to eq(100)
    end
  end

  describe "scopes" do
    describe ".with_rate_limit" do
      context "when rate limiting is enabled" do
        before do
          allow(Rails.application.config).to receive(:enable_query_rate_limiting).and_return(true)
        end

        it "raises error when rate limit exceeded" do
          allow(dummy_class).to receive(:rate_limit_exceeded?).and_return(true)
          
          expect {
            dummy_class.with_rate_limit("test_id")
          }.to raise_error(ActiveRecord::QueryAborted, "Rate limit exceeded. Please try again later.")
        end

        it "increments rate limit counter when not exceeded" do
          allow(dummy_class).to receive(:rate_limit_exceeded?).and_return(false)
          expect(dummy_class).to receive(:increment_rate_limit).with("test_id")
          
          result = dummy_class.with_rate_limit("test_id")
          expect(result).to be_a(dummy_class::MockRelation)
        end
      end

      context "when rate limiting is disabled" do
        before do
          allow(Rails.application.config).to receive(:enable_query_rate_limiting).and_return(false)
        end

        it "does not check rate limits" do
          expect(dummy_class).not_to receive(:rate_limit_exceeded?)
          dummy_class.with_rate_limit
        end
      end
    end

    describe ".with_cost_analysis" do
      it "raises error for expensive queries" do
        allow(dummy_class).to receive(:estimate_query_cost).and_return(15000)
        allow(Rails.logger).to receive(:warn)
        
        expect {
          dummy_class.with_cost_analysis
        }.to raise_error(ActiveRecord::QueryAborted, "Query too expensive. Please narrow your search criteria.")
        
        expect(Rails.logger).to have_received(:warn).with(/High cost query detected/)
      end

      it "allows queries within cost limit" do
        allow(dummy_class).to receive(:estimate_query_cost).and_return(5000)
        
        result = dummy_class.with_cost_analysis
        expect(result).to be_a(dummy_class::MockRelation)
      end
    end
  end

  describe "rate limiting methods" do
    let(:store) { QuerySecurity::MemoryRateLimitStore.new }

    before do
      allow(dummy_class).to receive(:rate_limit_store).and_return(store)
      allow(dummy_class).to receive(:rate_limiting_enabled?).and_return(true)
    end

    describe ".rate_limit_exceeded?" do
      it "returns false when under limit" do
        store.setex("query_rate_limit:DummyModel:test", 60, 50)
        expect(dummy_class.rate_limit_exceeded?("test")).to be false
      end

      it "returns true when at or over limit" do
        store.setex("query_rate_limit:DummyModel:test", 60, 100)
        expect(dummy_class.rate_limit_exceeded?("test")).to be true
      end

      it "returns false when rate limiting disabled" do
        allow(dummy_class).to receive(:rate_limiting_enabled?).and_return(false)
        expect(dummy_class.rate_limit_exceeded?).to be false
      end
    end

    describe ".increment_rate_limit" do
      it "creates new counter if none exists" do
        dummy_class.increment_rate_limit("test")
        expect(store.get("query_rate_limit:DummyModel:test")).to eq(1)
      end

      it "increments existing counter" do
        store.setex("query_rate_limit:DummyModel:test", 60, 5)
        dummy_class.increment_rate_limit("test")
        expect(store.get("query_rate_limit:DummyModel:test")).to eq(6)
      end

      it "does nothing when rate limiting disabled" do
        allow(dummy_class).to receive(:rate_limiting_enabled?).and_return(false)
        expect(store).not_to receive(:incr)
        dummy_class.increment_rate_limit("test")
      end
    end

    describe ".rate_limit_key" do
      it "generates key with identifier" do
        key = dummy_class.rate_limit_key("user_123")
        expect(key).to eq("query_rate_limit:DummyModel:user_123")
      end

      it "uses request identifier when none provided" do
        allow(dummy_class).to receive(:request_identifier).and_return("req_456")
        key = dummy_class.rate_limit_key
        expect(key).to eq("query_rate_limit:DummyModel:req_456")
      end
    end

    describe ".request_identifier" do
      it "uses RequestStore when available" do
        stub_const("RequestStore", Class.new)
        allow(RequestStore).to receive(:store).and_return({ request_id: "req_123" })
        expect(dummy_class.request_identifier).to eq("req_123")
      end

      it "uses Thread.current when RequestStore not available" do
        Thread.current[:request_id] = "thread_456"
        expect(dummy_class.request_identifier).to eq("thread_456")
      end

      it "returns 'unknown' as fallback" do
        Thread.current[:request_id] = nil
        expect(dummy_class.request_identifier).to eq("unknown")
      end
    end
  end

  describe "query cost estimation" do
    describe ".estimate_query_cost" do
      it "calculates cost from EXPLAIN output" do
        scope = dummy_class.where(id: 1)
        cost = dummy_class.estimate_query_cost(scope)
        expect(cost).to eq(510) # 500 + (100 * 0.1)
      end

      it "handles errors gracefully" do
        scope = dummy_class.where(id: 1)
        allow(dummy_class.connection).to receive(:execute).and_raise(StandardError.new("DB error"))
        allow(Rails.logger).to receive(:debug)
        
        cost = dummy_class.estimate_query_cost(scope)
        expect(cost).to eq(0)
        expect(Rails.logger).to have_received(:debug).with(/Could not estimate query cost/)
      end

      it "returns 0 for non-SQL scopes" do
        scope = double("NonSQLScope")
        cost = dummy_class.estimate_query_cost(scope)
        expect(cost).to eq(0)
      end
    end
  end

  describe "SQL injection prevention" do
    describe ".sanitize_like_query" do
      it "escapes special characters" do
        result = dummy_class.sanitize_like_query("test%_\\pattern")
        expect(result).to eq("test\\%\\_\\\\pattern")
      end

      it "returns empty string for blank input" do
        expect(dummy_class.sanitize_like_query(nil)).to eq("")
        expect(dummy_class.sanitize_like_query("")).to eq("")
      end
    end

    describe ".validate_cursor" do
      it "validates valid cursor" do
        data = { page: 1 }
        cursor = Base64.strict_encode64(data.to_json)
        result = dummy_class.validate_cursor(cursor)
        expect(result).to eq(cursor)
      end

      it "raises error for invalid cursor" do
        expect {
          dummy_class.validate_cursor("invalid_base64")
        }.to raise_error(ArgumentError, "Invalid cursor format")
      end

      it "returns nil for blank cursor" do
        expect(dummy_class.validate_cursor(nil)).to be_nil
        expect(dummy_class.validate_cursor("")).to be_nil
      end
    end

    describe ".validate_sort_column" do
      allowed = %w[id name created_at]
      
      it "allows whitelisted columns" do
        expect(dummy_class.validate_sort_column("name", allowed)).to eq("name")
      end

      it "returns default for invalid columns" do
        expect(dummy_class.validate_sort_column("evil_column", allowed)).to eq("created_at")
      end

      it "returns default for blank column" do
        expect(dummy_class.validate_sort_column(nil, allowed)).to eq("created_at")
      end
    end

    describe ".validate_sort_direction" do
      it "allows asc and desc" do
        expect(dummy_class.validate_sort_direction("asc")).to eq("asc")
        expect(dummy_class.validate_sort_direction("DESC")).to eq("desc")
      end

      it "returns desc for invalid direction" do
        expect(dummy_class.validate_sort_direction("invalid")).to eq("desc")
      end
    end
  end

  describe "pagination security" do
    describe ".validate_page_size" do
      it "returns default for invalid size" do
        expect(dummy_class.validate_page_size(0)).to eq(50)
        expect(dummy_class.validate_page_size(-1)).to eq(50)
      end

      it "caps at maximum size" do
        expect(dummy_class.validate_page_size(200, 100)).to eq(100)
      end

      it "allows valid sizes" do
        expect(dummy_class.validate_page_size(25)).to eq(25)
      end
    end

    describe ".validate_page_number" do
      it "returns 1 for invalid page" do
        expect(dummy_class.validate_page_number(0)).to eq(1)
        expect(dummy_class.validate_page_number(-1)).to eq(1)
      end

      it "allows valid page numbers" do
        expect(dummy_class.validate_page_number(5)).to eq(5)
      end
    end
  end

  describe "query complexity analysis" do
    describe ".analyze_query_complexity" do
      let(:scope) { dummy_class.where(id: 1) }

      before do
        allow(dummy_class).to receive(:count_joins).and_return(2)
        allow(dummy_class).to receive(:count_conditions).and_return(3)
        allow(dummy_class).to receive(:count_aggregations).and_return(1)
        allow(dummy_class).to receive(:count_subqueries).and_return(0)
      end

      it "returns complexity analysis" do
        analysis = dummy_class.analyze_query_complexity(scope)
        
        expect(analysis[:joins]).to eq(2)
        expect(analysis[:conditions]).to eq(3)
        expect(analysis[:aggregations]).to eq(1)
        expect(analysis[:subqueries]).to eq(0)
        expect(analysis[:score]).to eq(31) # (2*10) + (3*2) + (1*5) + (0*20)
      end

      it "logs warning for high complexity" do
        allow(dummy_class).to receive(:count_joins).and_return(15)
        allow(Rails.logger).to receive(:warn)
        
        dummy_class.analyze_query_complexity(scope)
        expect(Rails.logger).to have_received(:warn).with(/High complexity query detected/)
      end
    end

    describe "complexity counting methods (private)" do
      let(:scope) { dummy_class.where(id: 1) }

      it "counts joins" do
        allow(scope).to receive(:joins_values).and_return([1, 2])
        allow(scope).to receive(:left_outer_joins_values).and_return([3])
        count = dummy_class.send(:count_joins, scope)
        expect(count).to eq(3)
      end

      it "counts conditions" do
        allow(scope.where_clause).to receive(:predicates).and_return([1, 2, 3])
        count = dummy_class.send(:count_conditions, scope)
        expect(count).to eq(3)
      end

      it "counts aggregations" do
        allow(scope).to receive(:to_sql).and_return("SELECT COUNT(*), SUM(amount), AVG(price) GROUP BY category")
        count = dummy_class.send(:count_aggregations, scope)
        expect(count).to eq(4)
      end

      it "counts subqueries" do
        allow(scope).to receive(:to_sql).and_return("SELECT * FROM (SELECT id FROM users) WHERE id IN (SELECT user_id FROM orders)")
        count = dummy_class.send(:count_subqueries, scope)
        expect(count).to eq(2)
      end
    end
  end

  describe "instance methods" do
    describe "#validate_query_security" do
      it "returns true by default" do
        expect(dummy_object.validate_query_security).to be true
      end
    end

    describe "#query_security_enabled?" do
      it "returns true when enabled" do
        allow(Rails.application.config).to receive(:enable_query_security).and_return(true)
        expect(dummy_object.query_security_enabled?).to be true
      end

      it "returns false when disabled" do
        allow(Rails.application.config).to receive(:enable_query_security).and_return(false)
        expect(dummy_object.query_security_enabled?).to be false
      end

      it "returns false when table doesn't exist" do
        allow(dummy_class).to receive(:table_exists?).and_return(false)
        expect(dummy_object.query_security_enabled?).to be false
      end
    end
  end

  describe QuerySecurity::MemoryRateLimitStore do
    let(:store) { QuerySecurity::MemoryRateLimitStore.new }

    describe "#get" do
      it "returns stored value" do
        store.setex("key", 60, 42)
        expect(store.get("key")).to eq(42)
      end

      it "returns nil for non-existent key" do
        expect(store.get("nonexistent")).to be_nil
      end

      it "cleans up expired keys" do
        store.setex("expired", 0.001, 42)
        sleep 0.002
        expect(store.get("expired")).to be_nil
      end
    end

    describe "#setex" do
      it "sets value with expiration" do
        store.setex("key", 60, "value")
        expect(store.get("key")).to eq("value")
      end
    end

    describe "#incr" do
      it "increments existing value" do
        store.setex("counter", 60, 5)
        store.incr("counter")
        expect(store.get("counter")).to eq(6)
      end

      it "initializes to 1 for non-existent key" do
        store.incr("new_counter")
        expect(store.get("new_counter")).to eq(1)
      end
    end

    describe "#exists?" do
      it "returns true for existing key" do
        store.setex("key", 60, "value")
        expect(store.exists?("key")).to be true
      end

      it "returns false for non-existent key" do
        expect(store.exists?("nonexistent")).to be false
      end

      it "returns false for expired key" do
        store.setex("expired", 0.001, "value")
        sleep 0.002
        expect(store.exists?("expired")).to be false
      end
    end
  end
end