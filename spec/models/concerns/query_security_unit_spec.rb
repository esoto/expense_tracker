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
      it "returns current scope or all without modification" do
        # Test that the scope doesn't modify the SQL query itself
        base_sql = model_class.all.to_sql
        allow(model_class).to receive(:rate_limit_exceeded?).and_return(false)
        allow(model_class).to receive(:increment_rate_limit)

        scoped_sql = model_class.with_rate_limit.to_sql
        expect(scoped_sql).to eq(base_sql)
      end

      it "works with existing scopes" do
        allow(model_class).to receive(:rate_limit_exceeded?).and_return(false)
        allow(model_class).to receive(:increment_rate_limit)

        # Test that it preserves existing WHERE conditions
        base_query = model_class.where(id: 1)
        scoped_query = base_query.with_rate_limit

        expect(scoped_query.to_sql).to include('WHERE')
        expect(scoped_query.to_sql).to include('"id" = 1') if model_class.column_names.include?('id')
      end
    end

    describe ".with_cost_analysis" do
      it "returns current scope without SQL modification" do
        allow(model_class).to receive(:estimate_query_cost).and_return(5000)

        base_sql = model_class.all.to_sql
        scoped_sql = model_class.with_cost_analysis.to_sql
        expect(scoped_sql).to eq(base_sql)
      end

      it "preserves existing query conditions" do
        allow(model_class).to receive(:estimate_query_cost).and_return(5000)

        if model_class.column_names.include?('created_at')
          base_query = model_class.where('created_at > ?', 1.day.ago)
          scoped_query = base_query.with_cost_analysis

          expect(scoped_query.to_sql).to include('created_at')
          expect(scoped_query.to_sql).to include('>')
        end
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
RSpec.describe QuerySecurity::MemoryRateLimitStore do
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

# Apply shared examples to each model that uses QuerySecurity concern
[ Expense ].each do |model_class|
  RSpec.describe model_class, type: :model, unit: true do
    it_behaves_like "QuerySecurity concern"
  end
end
