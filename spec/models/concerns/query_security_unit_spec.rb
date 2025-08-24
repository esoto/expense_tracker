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
      context "when rate limiting is disabled" do
        before do
          Rails.application.config.enable_query_rate_limiting = false
        end

        it "does not enforce rate limits and returns relation" do
          allow(model_class).to receive(:rate_limiting_enabled?).and_return(false)
          result = model_class.with_rate_limit
          expect(result).to be_a(ActiveRecord::Relation)
        end
      end

      context "when rate limiting is enabled" do
        before do
          Rails.application.config.enable_query_rate_limiting = true
        end

        it "checks rate limits" do
          allow(model_class).to receive(:rate_limit_exceeded?).and_return(false)
          allow(model_class).to receive(:increment_rate_limit)
          result = model_class.with_rate_limit("test_id")
          expect(result).to be_a(ActiveRecord::Relation)
        end
      end
    end

    describe ".with_cost_analysis" do
      it "returns relation when query cost is acceptable" do
        allow(model_class).to receive(:estimate_query_cost).and_return(5000)
        result = model_class.with_cost_analysis
        expect(result).to be_a(ActiveRecord::Relation)
      end
    end
  end

  describe "SQL injection prevention" do
    describe ".sanitize_like_query" do
      it "escapes special characters" do
        result = model_class.sanitize_like_query("test%_\\pattern")
        expect(result).to eq("test\\%\\_\\\\pattern")
      end

      it "returns empty string for blank input" do
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
      let(:allowed) { %w[id name created_at] }
      it "allows whitelisted columns" do
        expect(model_class.validate_sort_column("name", allowed)).to eq("name")
      end

      it "returns default for invalid columns" do
        expect(model_class.validate_sort_column("evil_column", allowed)).to eq("created_at")
      end

      it "returns default for blank column" do
        expect(model_class.validate_sort_column(nil, allowed)).to eq("created_at")
      end
    end

    describe ".validate_sort_direction" do
      it "allows asc and desc" do
        expect(model_class.validate_sort_direction("asc")).to eq("asc")
        expect(model_class.validate_sort_direction("DESC")).to eq("desc")
      end

      it "returns desc for invalid direction" do
        expect(model_class.validate_sort_direction("invalid")).to eq("desc")
      end
    end
  end

  describe "pagination security" do
    describe ".validate_page_size" do
      it "returns default for invalid size" do
        expect(model_class.validate_page_size(0)).to eq(50)
        expect(model_class.validate_page_size(-1)).to eq(50)
      end

      it "caps at maximum size" do
        expect(model_class.validate_page_size(200, 100)).to eq(100)
      end

      it "allows valid sizes" do
        expect(model_class.validate_page_size(25)).to eq(25)
      end
    end

    describe ".validate_page_number" do
      it "returns 1 for invalid page" do
        expect(model_class.validate_page_number(0)).to eq(1)
        expect(model_class.validate_page_number(-1)).to eq(1)
      end

      it "allows valid page numbers" do
        expect(model_class.validate_page_number(5)).to eq(5)
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
        expect(model_instance.query_security_enabled?).to be_in([true, false])
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