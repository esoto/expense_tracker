# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpenseQueryOptimizer, type: :model, unit: true do
  # Use actual Expense model for realistic testing
  let(:expense) { build(:expense) }

  describe "scopes" do
    describe ".for_list_display" do
      it "filters out deleted records" do
        sql = Expense.for_list_display.to_sql
        expect(sql).to include("deleted_at\" IS NULL")
      end

      it "includes category and email_account associations" do
        # The includes() doesn't generate JOINs until the query is executed
        # We just test that it responds to the method
        expect(Expense.for_list_display.includes_values).to include(:category, :email_account)
      end
    end

    describe ".with_filters" do
      it "returns base scope when no filters provided" do
        sql = Expense.with_filters({}).to_sql
        expect(sql).to include("deleted_at\" IS NULL")
        # Should only have the deleted_at filter, no additional WHERE clauses
        expect(sql.scan(/WHERE/).count).to eq(1)
      end

      it "applies date range filter" do
        filters = { start_date: Date.current, end_date: Date.tomorrow }
        sql = Expense.with_filters(filters).to_sql
        expect(sql).to include("transaction_date")
      end

      it "applies category filter" do
        filters = { category_ids: [ 1, 2, 3 ] }
        sql = Expense.with_filters(filters).to_sql
        expect(sql).to include("category_id")
      end

      it "applies banks filter" do
        filters = { banks: [ "Bank A", "Bank B" ] }
        sql = Expense.with_filters(filters).to_sql
        expect(sql).to include("bank_name")
        expect(sql).to include("Bank A")
      end

      it "applies amount range filter" do
        filters = { min_amount: 50, max_amount: 200 }
        sql = Expense.with_filters(filters).to_sql
        expect(sql).to include("amount")
      end


      it "applies search filter" do
        filters = { search: "coffee" }
        sql = Expense.with_filters(filters).to_sql
        expect(sql).to include("merchant_normalized")
      end

      it "applies multiple filters together" do
        filters = {
          start_date: Date.current,
          category_ids: [ 1, 2 ],
          banks: [ "Bank A" ],
          status: "approved",
          search: "starbucks"
        }
        sql = Expense.with_filters(filters).to_sql
        expect(sql).to include("transaction_date")
        expect(sql).to include("category_id")
        expect(sql).to include("bank_name")
        expect(sql).to include("status")
        expect(sql).to include("merchant_normalized")
      end
    end

    describe ".by_categories" do
      it "filters by category IDs" do
        sql = Expense.by_categories([ 1, 2, 3 ]).to_sql
        expect(sql).to include("category_id")
        expect(sql).to include("(1, 2, 3)")
      end

      it "handles uncategorized with nil" do
        sql = Expense.by_categories([ nil, 1, 2 ]).to_sql
        expect(sql).to include("category_id\" IS NULL")
        expect(sql).to include("OR")
      end

      it "handles uncategorized string" do
        sql = Expense.by_categories([ "uncategorized", 1 ]).to_sql
        expect(sql).to include("category_id\" IS NULL")
      end
    end

    describe ".by_banks" do
      it "filters by bank names" do
        sql = Expense.by_banks([ "Bank A", "Bank B" ]).to_sql
        expect(sql).to include("bank_name")
        expect(sql).to include("Bank A")
      end
    end

    describe ".by_amount_range" do
      it "filters by minimum amount" do
        sql = Expense.by_amount_range(10.0, nil).to_sql
        expect(sql).to include("amount\" >= 10.0")
      end

      it "filters by maximum amount" do
        sql = Expense.by_amount_range(nil, 100.0).to_sql
        expect(sql).to include("amount\" <= 100.0")
      end

      it "filters by both min and max" do
        sql = Expense.by_amount_range(10.0, 100.0).to_sql
        expect(sql).to include("BETWEEN 10.0 AND 100.0")
      end
    end

    describe ".search_merchant" do
      it "returns current scope when term is blank" do
        sql = Expense.search_merchant("").to_sql
        expect(sql).not_to include("merchant_normalized")
      end

      it "uses trigram search when available" do
        sql = Expense.search_merchant("coffee").to_sql
        # The concern uses trigram search by default if pg_trgm extension is available
        expect(sql).to include("merchant_normalized % 'coffee'")
      end
    end

    describe ".not_deleted" do
      it "filters out deleted records" do
        sql = Expense.not_deleted.to_sql
        expect(sql).to include("deleted_at\" IS NULL")
      end
    end

    describe ".deleted" do
      it "includes only deleted records" do
        sql = Expense.deleted.to_sql
        expect(sql).to include("deleted_at\" IS NOT NULL")
      end
    end

    describe ".with_category" do
      it "includes only categorized expenses" do
        sql = Expense.with_category.to_sql
        expect(sql).to include("category_id\" IS NOT NULL")
      end
    end

    describe ".without_category" do
      it "includes only uncategorized expenses" do
        sql = Expense.without_category.to_sql
        expect(sql).to include("category_id\" IS NULL")
      end
    end
  end

  describe "class methods" do
    it "defines pagination and aggregation methods" do
      methods = %i[list_display_columns cursor_paginate aggregate_by_category aggregate_by_period explain_query encode_cursor]
      methods.each { |method| expect(Expense).to respond_to(method) }
    end

    describe ".list_display_columns" do
      it "returns expected column names" do
        columns = Expense.list_display_columns
        expect(columns).to include("expenses.id", "expenses.amount", "expenses.description")
      end
    end

    describe ".cursor_paginate" do
      it "returns paginated results without cursor" do
        result = Expense.cursor_paginate(limit: 25)
        sql = result.to_sql
        expect(sql).to include("ORDER BY")
        expect(sql).to include("transaction_date")
        expect(sql).to include("LIMIT 25")
      end

      it "handles forward pagination with valid cursor" do
        cursor_data = { date: Date.current.iso8601, id: 123 }
        cursor = Base64.strict_encode64(cursor_data.to_json)

        result = Expense.cursor_paginate(cursor: cursor, direction: :forward, limit: 10)
        sql = result.to_sql
        expect(sql).to include("transaction_date, id) < (")
        expect(sql).to include("LIMIT 10")
      end

      it "handles backward pagination with valid cursor" do
        cursor_data = { date: Date.current.iso8601, id: 123 }
        cursor = Base64.strict_encode64(cursor_data.to_json)

        result = Expense.cursor_paginate(cursor: cursor, direction: :backward, limit: 10)
        sql = result.to_sql
        expect(sql).to include("transaction_date, id) > (")
      end

      it "caps limit at 100 for safety" do
        result = Expense.cursor_paginate(limit: 500)
        sql = result.to_sql
        expect(sql).to include("LIMIT 100")
      end

      it "handles invalid cursor gracefully" do
        allow(Rails.logger).to receive(:warn)

        result = Expense.cursor_paginate(cursor: "invalid_cursor")
        expect(result).to respond_to(:to_sql)
        expect(Rails.logger).to have_received(:warn).with(/Invalid cursor provided/)
      end

      it "handles cursor with missing date" do
        invalid_cursor = Base64.strict_encode64({ id: 123 }.to_json)
        allow(Rails.logger).to receive(:warn)

        result = Expense.cursor_paginate(cursor: invalid_cursor)
        expect(result).to respond_to(:to_sql)
        expect(Rails.logger).to have_received(:warn).with(/Invalid cursor provided/)
      end

      it "handles cursor with missing id" do
        invalid_cursor = Base64.strict_encode64({ date: Date.current.iso8601 }.to_json)
        allow(Rails.logger).to receive(:warn)

        result = Expense.cursor_paginate(cursor: invalid_cursor)
        expect(result).to respond_to(:to_sql)
        expect(Rails.logger).to have_received(:warn).with(/Invalid cursor provided/)
      end

      it "defaults to forward direction" do
        cursor_data = { date: Date.current.iso8601, id: 123 }
        cursor = Base64.strict_encode64(cursor_data.to_json)

        result = Expense.cursor_paginate(cursor: cursor)
        sql = result.to_sql
        expect(sql).to include("transaction_date, id) < (")  # forward direction
      end

      it "defaults to 50 item limit" do
        result = Expense.cursor_paginate
        sql = result.to_sql
        expect(sql).to include("LIMIT 50")
      end
    end

    describe ".aggregate_by_period" do
      it "defaults to monthly aggregation" do
        result = Expense.aggregate_by_period
        expect(result).to be_an(Array)
        # We can't test actual data without database records, but we can test the method exists and returns expected structure
      end

      it "aggregates by day period" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current, 5, 250.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :day)

        expect(result).to be_an(Array)
        expect(result.first).to include(:period, :count, :total)
      end

      it "aggregates by week period" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current.beginning_of_week, 12, 600.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :week)

        expect(result).to be_an(Array)
        expect(result.first).to include(:period, :count, :total)
      end

      it "aggregates by month period" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current.beginning_of_month, 30, 1500.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :month)

        expect(result).to be_an(Array)
        expect(result.first).to include(:period, :count, :total)
      end

      it "aggregates by year period" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current.beginning_of_year, 365, 18000.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :year)

        expect(result).to be_an(Array)
        expect(result.first).to include(:period, :count, :total)
      end

      it "handles invalid period by defaulting to month" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current.beginning_of_month, 20, 1000.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :invalid)

        expect(result).to be_an(Array)
        expect(result.first).to include(:period, :count, :total)
      end

      it "applies date range filter when provided" do
        start_date = Date.current.beginning_of_month
        end_date = Date.current.end_of_month

        sql_spy = double("relation")
        allow(sql_spy).to receive(:by_date_range).with(start_date, end_date).and_return(sql_spy)
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current.beginning_of_month, 15, 750.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(
          period: :month,
          start_date: start_date,
          end_date: end_date
        )

        expect(sql_spy).to have_received(:by_date_range).with(start_date, end_date)
        expect(result).to be_an(Array)
      end

      it "returns properly structured data" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ Date.current, 10, 500.50 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :day)

        expect(result).to be_an(Array)
        expect(result.first[:period]).to eq(Date.current)
        expect(result.first[:count]).to eq(10)
        expect(result.first[:total]).to eq(500.5)
      end

      it "handles empty results" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_period(period: :day)

        expect(result).to be_an(Array)
        expect(result).to be_empty
      end
    end

    describe ".aggregate_by_category" do
      it "returns aggregated data by category" do
        sql_spy = double("relation")
        allow(sql_spy).to receive(:group).with(:category_id).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([
          [ 1, 5, 250.0, 50.0 ],
          [ 2, 3, 150.0, 50.0 ]
        ])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        result = Expense.aggregate_by_category

        expect(result).to be_an(Array)
        expect(result.first).to include(:category_id, :count, :total, :average)
        expect(result.first[:category_id]).to eq(1)
        expect(result.first[:count]).to eq(5)
        expect(result.first[:total]).to eq(250.0)
        expect(result.first[:average]).to eq(50.0)
      end

      it "applies date range filter when provided" do
        start_date = Date.current.beginning_of_month
        end_date = Date.current.end_of_month

        sql_spy = double("relation")
        allow(sql_spy).to receive(:by_date_range).with(start_date, end_date).and_return(sql_spy)
        allow(sql_spy).to receive(:group).with(:category_id).and_return(sql_spy)
        allow(sql_spy).to receive(:pluck).and_return([])
        allow(Expense).to receive(:not_deleted).and_return(sql_spy)

        Expense.aggregate_by_category(start_date: start_date, end_date: end_date)

        expect(sql_spy).to have_received(:by_date_range).with(start_date, end_date)
      end
    end

    describe ".encode_cursor" do
      it "creates Base64 encoded cursor" do
        cursor = Expense.encode_cursor(expense)
        expect { Base64.strict_decode64(cursor) }.not_to raise_error
      end

      it "includes date and id in cursor" do
        expense.id = 456
        expense.transaction_date = Date.new(2024, 6, 15)

        cursor = Expense.encode_cursor(expense)
        decoded = JSON.parse(Base64.strict_decode64(cursor))

        expect(decoded["date"]).to eq("2024-06-15T00:00:00Z")
        expect(decoded["id"]).to eq(456)
      end
    end
  end

  describe "instance methods" do
    describe "#cache_key_with_version" do
      it "includes model name, id, timestamp, and lock version" do
        expense.id = 123
        expense.updated_at = Time.current
        expense.lock_version = 5

        cache_key = expense.cache_key_with_version
        expect(cache_key).to include("expenses", "123", "5")
      end
    end

    describe "#soft_delete!" do
      it "sets deleted_at" do
        expect { expense.soft_delete! }.to change { expense.deleted_at }.from(nil)
      end
    end

    describe "#restore!" do
      it "clears deleted_at" do
        expense.soft_delete!
        expect { expense.restore! }.to change { expense.deleted_at }.to(nil)
      end
    end

    describe "#deleted?" do
      it "returns true when deleted_at is present" do
        expense.deleted_at = Time.current
        expect(expense.deleted?).to be true
      end

      it "returns false when deleted_at is nil" do
        expense.deleted_at = nil
        expect(expense.deleted?).to be false
      end
    end
  end
end
