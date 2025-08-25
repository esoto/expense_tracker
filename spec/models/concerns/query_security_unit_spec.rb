# frozen_string_literal: true

require "rails_helper"

# Shared examples for testing QuerySecurity concern
RSpec.shared_examples "QuerySecurity concern" do
  let(:model_class) { described_class }
  let(:model_instance) { build_stubbed(described_class.name.underscore.to_sym) }

  describe "QuerySecurity concern inclusion" do
    it "includes the QuerySecurity concern" do
      expect(model_class.included_modules).to include(QuerySecurity)
    end

    it "responds to QuerySecurity class methods" do
      expect(model_class).to respond_to(:with_rate_limit)
      expect(model_class).to respond_to(:with_cost_analysis)
      expect(model_class).to respond_to(:sanitize_like_query)
      expect(model_class).to respond_to(:validate_cursor)
      expect(model_class).to respond_to(:validate_sort_column)
      expect(model_class).to respond_to(:validate_sort_direction)
      expect(model_class).to respond_to(:validate_page_size)
      expect(model_class).to respond_to(:validate_page_number)
    end

    it "responds to QuerySecurity instance methods" do
      expect(model_instance).to respond_to(:query_security_enabled?)
      expect(model_instance).to respond_to(:validate_query_security)
    end
  end

  describe "constants" do
    it "has access to QuerySecurity constants" do
      expect(QuerySecurity::MAX_QUERY_COST).to eq(10000)
      expect(QuerySecurity::MAX_ROWS_PER_REQUEST).to eq(1000)
      expect(QuerySecurity::RATE_LIMIT_WINDOW).to eq(1.minute)
      expect(QuerySecurity::MAX_REQUESTS_PER_WINDOW).to eq(100)
    end
  end

  describe "scopes" do
    describe ".with_rate_limit" do
      it "calls rate_limit_exceeded? and increment_rate_limit for security validation" do
        expect(model_class).to receive(:rate_limit_exceeded?).with(nil).and_return(false)
        expect(model_class).to receive(:increment_rate_limit).with(nil)
        model_class.with_rate_limit
      end

      it "calls rate_limit_exceeded? with provided identifier" do
        expect(model_class).to receive(:rate_limit_exceeded?).with("user_123").and_return(false)
        expect(model_class).to receive(:increment_rate_limit).with("user_123")
        model_class.with_rate_limit("user_123")
      end

      it "raises QueryAborted when rate limit exceeded" do
        expect(model_class).to receive(:rate_limit_exceeded?).and_return(true)
        expect {
          model_class.with_rate_limit
        }.to raise_error(ActiveRecord::QueryAborted, "Rate limit exceeded. Please try again later.")
      end

      it "does not raise error when rate limit not exceeded" do
        allow(model_class).to receive(:rate_limit_exceeded?).and_return(false)
        allow(model_class).to receive(:increment_rate_limit)
        expect { model_class.with_rate_limit }.not_to raise_error
      end
    end

    describe ".with_cost_analysis" do
      it "calls estimate_query_cost to analyze query performance" do
        expect(model_class).to receive(:estimate_query_cost).and_return(5000)
        model_class.with_cost_analysis
      end

      it "raises QueryAborted when query cost exceeds limit" do
        expect(model_class).to receive(:estimate_query_cost).and_return(15000)
        expect(Rails.logger).to receive(:warn).with(/High cost query detected/)
        expect {
          model_class.with_cost_analysis
        }.to raise_error(ActiveRecord::QueryAborted, "Query too expensive. Please narrow your search criteria.")
      end

      it "does not raise error when cost is acceptable" do
        allow(model_class).to receive(:estimate_query_cost).and_return(5000)
        expect { model_class.with_cost_analysis }.not_to raise_error
      end
    end
  end

  describe "SQL injection prevention" do
    describe ".sanitize_like_query" do
      it "escapes special characters to prevent SQL injection" do
        result = model_class.sanitize_like_query("test%_\\pattern")
        expect(result).to eq("test\\%\\_\\\\pattern")

        # Test that escaped pattern works safely in SQL
        if model_class.column_names.include?('description')
          query = model_class.where("description LIKE ?", "%#{result}%")
          expect(query.to_sql).to include('LIKE')
          expect(query.to_sql).to include('test\\%\\_\\\\pattern')
        end
      end

      it "returns safe empty string for blank input" do
        expect(model_class.sanitize_like_query(nil)).to eq("")
        expect(model_class.sanitize_like_query("")).to eq("")
      end
    end

    describe ".validate_cursor" do
      it "validates valid cursor" do
        data = { page: 1 }
        cursor = Base64.strict_encode64(data.to_json)
        result = model_class.validate_cursor(cursor)
        expect(result).to eq(cursor)
      end

      it "raises error for invalid cursor" do
        expect {
          model_class.validate_cursor("invalid_base64")
        }.to raise_error(ArgumentError, "Invalid cursor format")
      end

      it "returns nil for blank cursor" do
        expect(model_class.validate_cursor(nil)).to be_nil
        expect(model_class.validate_cursor("")).to be_nil
      end
    end

    describe ".validate_sort_column" do
      let(:allowed) { %w[id created_at] }

      it "allows whitelisted columns in SQL ORDER BY" do
        column = model_class.validate_sort_column("id", allowed)
        expect(column).to eq("id")

        # Test that validated column works safely in ORDER BY
        if model_class.column_names.include?('id')
          query = model_class.order(column => :asc)
          expect(query.to_sql).to include('ORDER BY')
          expect(query.to_sql).to include('"id"')
        end
      end

      it "prevents SQL injection by rejecting invalid columns" do
        column = model_class.validate_sort_column("evil_column; DROP TABLE users; --", allowed)
        expect(column).to eq("created_at") # Safe default

        # Ensure the malicious input doesn't appear in SQL
        if model_class.column_names.include?('created_at')
          query = model_class.order(column => :desc)
          expect(query.to_sql).not_to include("DROP TABLE")
          expect(query.to_sql).not_to include("evil_column")
        end
      end

      it "returns safe default for blank column" do
        column = model_class.validate_sort_column(nil, allowed)
        expect(column).to eq("created_at")
      end
    end

    describe ".validate_sort_direction" do
      it "allows safe ASC and DESC in SQL ORDER BY" do
        expect(model_class.validate_sort_direction("asc")).to eq("asc")
        expect(model_class.validate_sort_direction("DESC")).to eq("desc")

        # Test that validated direction works in SQL
        if model_class.column_names.include?('id')
          asc_query = model_class.order(id: model_class.validate_sort_direction("asc"))
          desc_query = model_class.order(id: model_class.validate_sort_direction("DESC"))

          expect(asc_query.to_sql).to include('ASC')
          expect(desc_query.to_sql).to include('DESC')
        end
      end

      it "prevents SQL injection by sanitizing invalid directions" do
        direction = model_class.validate_sort_direction("ASC; DROP TABLE users; --")
        expect(direction).to eq("desc") # Safe default

        # Ensure malicious input doesn't appear in SQL
        if model_class.column_names.include?('id')
          query = model_class.order(id: direction)
          expect(query.to_sql).not_to include("DROP TABLE")
          expect(query.to_sql).to include('DESC')
        end
      end
    end
  end

  describe "pagination security" do
    describe ".validate_page_size" do
      it "prevents resource exhaustion with safe LIMIT values" do
        page_size = model_class.validate_page_size(0)
        expect(page_size).to eq(50) # Safe default

        # Test that validated size works safely in SQL LIMIT
        query = model_class.limit(page_size)
        expect(query.to_sql).to include('LIMIT 50')
      end

      it "caps at maximum size to prevent memory issues" do
        page_size = model_class.validate_page_size(200, 100)
        expect(page_size).to eq(100)

        # Test that capped size works in SQL
        query = model_class.limit(page_size)
        expect(query.to_sql).to include('LIMIT 100')
        expect(query.to_sql).not_to include('LIMIT 200')
      end

      it "allows valid sizes in SQL LIMIT clause" do
        page_size = model_class.validate_page_size(25)
        expect(page_size).to eq(25)

        query = model_class.limit(page_size)
        expect(query.to_sql).to include('LIMIT 25')
      end
    end

    describe ".validate_page_number" do
      it "prevents negative OFFSET values in SQL" do
        page = model_class.validate_page_number(0)
        expect(page).to eq(1) # Safe minimum

        page = model_class.validate_page_number(-1)
        expect(page).to eq(1) # Safe minimum
      end

      it "allows valid page numbers for SQL OFFSET calculation" do
        page = model_class.validate_page_number(5)
        expect(page).to eq(5)

        # Test OFFSET calculation (page - 1) * page_size
        offset = (page - 1) * 10
        query = model_class.limit(10).offset(offset)
        expect(query.to_sql).to include('LIMIT 10')
        expect(query.to_sql).to include('OFFSET 40')
      end
    end
  end

  describe "instance methods" do
    describe "#validate_query_security" do
      it "returns true by default" do
        expect(model_instance.validate_query_security).to be true
      end
    end

    describe "#query_security_enabled?" do
      it "responds to query_security_enabled?" do
        expect(model_instance.query_security_enabled?).to be_in([ true, false ])
      end
    end
  end
end

# Test the MemoryRateLimitStore independently
RSpec.describe QuerySecurity::MemoryRateLimitStore, unit: true do
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

# Comprehensive tests for QuerySecurity concern methods
RSpec.describe QuerySecurity, unit: true do
  # Create a test class that includes the concern for isolated testing
  let(:test_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "expenses" # Use existing table for testing
      include QuerySecurity
    end
  end

  describe "rate limiting functionality" do
    describe ".rate_limit_exceeded?" do
      it "executes rate limiting when properly configured" do
        # Set up actual Rails configuration to enable rate limiting
        Rails.application.config.class_eval do
          attr_accessor :enable_query_rate_limiting
        end

        Rails.application.config.enable_query_rate_limiting = true

        begin
          store = test_class.rate_limit_store
          identifier = test_class.request_identifier
          key = test_class.rate_limit_key(identifier)

          # Test under limit scenario - executes lines 47-52
          store.setex(key, 60, 50)
          expect(test_class.rate_limit_exceeded?).to be false

          # Test over limit scenario - executes lines 47-52
          store.setex(key, 60, 150)
          expect(test_class.rate_limit_exceeded?).to be true

        ensure
          Rails.application.config.enable_query_rate_limiting = nil
          Rails.application.config.class_eval do
            remove_method :enable_query_rate_limiting if method_defined?(:enable_query_rate_limiting)
            remove_method :enable_query_rate_limiting= if method_defined?(:enable_query_rate_limiting=)
          end
        end
      end
    end

    describe ".increment_rate_limit" do
      it "executes increment rate limiting when properly configured" do
        Rails.application.config.class_eval do
          attr_accessor :enable_query_rate_limiting
        end

        Rails.application.config.enable_query_rate_limiting = true

        begin
          store = test_class.rate_limit_store
          identifier = test_class.request_identifier
          key = test_class.rate_limit_key(identifier)

          # Clear any existing data
          store.instance_variable_get(:@store).clear
          store.instance_variable_get(:@expires).clear

          # Test creating new counter - executes lines 54-65
          test_class.increment_rate_limit
          expect(store.get(key)).to eq(1)

          # Test incrementing existing counter
          test_class.increment_rate_limit
          expect(store.get(key)).to eq(2)

        ensure
          Rails.application.config.enable_query_rate_limiting = nil
          Rails.application.config.class_eval do
            remove_method :enable_query_rate_limiting if method_defined?(:enable_query_rate_limiting)
            remove_method :enable_query_rate_limiting= if method_defined?(:enable_query_rate_limiting=)
          end
        end
      end
    end

    describe ".request_identifier" do
      it "uses Thread-local request_id when available" do
        Thread.current[:request_id] = "test_thread"
        expect(test_class.request_identifier).to eq("test_thread")
        Thread.current[:request_id] = nil # Clean up
      end

      it "returns 'unknown' as fallback" do
        Thread.current[:request_id] = nil
        expect(test_class.request_identifier).to eq("unknown")
      end
    end
  end

  describe "query cost estimation" do
    describe ".estimate_query_cost" do
      it "handles database errors gracefully" do
        invalid_scope = double("scope", to_sql: "INVALID SQL SYNTAX", respond_to?: true)
        allow(Rails.logger).to receive(:debug)
        cost = test_class.estimate_query_cost(invalid_scope)
        expect(cost).to eq(0)
      end
    end
  end

  describe "query complexity analysis" do
    describe ".analyze_query_complexity" do
      it "logs warning for high complexity queries when score exceeds threshold" do
        complex_scope = double("scope",
          joins_values: Array.new(15, "table"), # 15 joins = 150 points
          left_outer_joins_values: [],
          where_clause: double(predicates: []),
          to_sql: "SELECT * FROM table"
        )

        expect(Rails.logger).to receive(:warn).with(/High complexity query detected/)
        test_class.analyze_query_complexity(complex_scope)
      end
    end
  end

  describe "edge cases and error handling" do
    describe "advanced injection scenarios" do
      it "handles Unicode characters safely in sanitize_like_query" do
        unicode_input = "café_münü%ñoño"
        result = test_class.sanitize_like_query(unicode_input)
        expect(result).to eq("café\\_münü\\%ñoño")
      end

      it "handles malformed JSON in validate_cursor" do
        bad_cursor = Base64.strict_encode64("{ invalid json")
        expect {
          test_class.validate_cursor(bad_cursor)
        }.to raise_error(ArgumentError, "Invalid cursor format")
      end
    end
  end
end

# Apply shared examples to each model that uses QuerySecurity concern
[ Expense ].each do |model_class|
  RSpec.describe model_class, type: :model, unit: true do
    it_behaves_like "QuerySecurity concern"
  end
end
