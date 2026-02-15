# frozen_string_literal: true

require "rails_helper"

RSpec.describe Expense, type: :model, unit: true do
  # Test QuerySecurity concern - moved to query_security_unit_spec.rb to avoid loading issues
  # it_behaves_like "QuerySecurity concern"
  # Use build for true unit testing
  let(:email_account) { build(:email_account, id: 1, bank_name: "BCR") }
  let(:category) { build(:category, id: 1, name: "Food") }
  let(:ml_category) { build(:category, id: 2, name: "Transport") }

  # For tests that need real database records
  let(:real_email_account) { create(:email_account, email: "test_#{SecureRandom.hex(4)}@example.com", bank_name: "BCR") }
  let(:real_category) { create(:category, name: "Food") }
  let(:real_ml_category) { create(:category, name: "Transport") }
  let(:expense) do
    build(:expense,
      id: 1,
      email_account: email_account,
      category: category,
      ml_suggested_category: ml_category,
      amount: 25000.0,
      currency: :crc,
      transaction_date: Date.current,
      status: :processed,
      merchant_name: "Super ABC",
      merchant_normalized: "super abc",
      description: "Purchase at Super ABC",
      ml_confidence: 0.85,
      ml_confidence_explanation: "High confidence based on merchant",
      ml_correction_count: 0,
      parsed_data: '{"original_amount": "25000"}')
  end

  describe "included modules" do
    it "includes ExpenseQueryOptimizer" do
      expect(described_class.ancestors).to include(ExpenseQueryOptimizer)
    end

    it "includes QuerySecurity" do
      expect(described_class.ancestors).to include(QuerySecurity)
    end
  end

  describe "validations" do
    subject { build(:expense, email_account: email_account) }

    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    it { should validate_presence_of(:transaction_date) }
    it { should validate_presence_of(:status) }
    it { should define_enum_for(:status).with_values(pending: 0, processed: 1, failed: 2, duplicate: 3) }
    it { should validate_presence_of(:currency) }
  end

  describe "associations" do
    it { should belong_to(:email_account).optional }
    it { should belong_to(:category).optional }
    it { should belong_to(:ml_suggested_category).class_name("Category").with_foreign_key("ml_suggested_category_id").optional }
    it { should have_many(:pattern_feedbacks).dependent(:destroy) }
    it { should have_many(:pattern_learning_events).dependent(:destroy) }
    it { should have_many(:bulk_operation_items).dependent(:destroy) }
  end

  describe "enums" do
    it { should define_enum_for(:currency).with_values(crc: 0, usd: 1, eur: 2) }
    it { should define_enum_for(:status).with_values(pending: 0, processed: 1, failed: 2, duplicate: 3) }
  end

  describe "callbacks" do
    describe "before_save :normalize_merchant_name" do
      it "normalizes merchant name on save" do
        expense = build(:expense,
          email_account: real_email_account,
          merchant_name: "  SUPER-ABC!!!  ")

        expense.save!
        expect(expense.merchant_normalized).to eq("super abc")
      end

      it "handles nil merchant name" do
        expense = build(:expense,
          email_account: real_email_account,
          merchant_name: nil,
          merchant_normalized: nil)

        expense.save!
        expect(expense.merchant_normalized).to be_nil
      end

      it "only updates when merchant_name changes" do
        expense = create(:expense,
          email_account: real_email_account,
          merchant_name: "Store ABC",
          merchant_normalized: "store abc")

        expense.update!(amount: 5000)
        expect(expense.merchant_normalized).to eq("store abc")
      end
    end

    describe "after_commit callbacks" do
      let(:expense) { create(:expense, email_account: real_email_account) }

      it "triggers clear_dashboard_cache" do
        expect(Services::DashboardService).to receive(:clear_cache).at_least(:once)
        expense.update!(amount: 10000)
      end

      it "triggers metrics refresh on create" do
        expect(MetricsRefreshJob).to receive(:enqueue_debounced)
        create(:expense, email_account: real_email_account)
      end

      it "triggers metrics refresh on update" do
        expect(MetricsRefreshJob).to receive(:enqueue_debounced).at_least(:once)
        expense.update!(amount: 10000)
      end

      it "triggers metrics refresh on destroy" do
        expect(MetricsRefreshJob).to receive(:enqueue_debounced).at_least(:once)
        expense.destroy
      end
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by transaction_date descending" do
        query = described_class.recent
        expect(query.to_sql).to include("ORDER BY")
        expect(query.to_sql).to include("transaction_date")
        expect(query.to_sql).to include("DESC")
      end
    end

    describe ".by_status" do
      it "filters by status" do
        query = described_class.by_status("processed")
        expect(query.to_sql).to include('"expenses"."status" = 1')
      end
    end

    describe ".by_date_range" do
      it "filters by date range" do
        start_date = Date.new(2025, 1, 1)
        end_date = Date.new(2025, 1, 31)
        query = described_class.by_date_range(start_date, end_date)
        expect(query.to_sql).to include("transaction_date")
      end
    end

    describe ".by_amount_range" do
      it "filters by amount range" do
        query = described_class.by_amount_range(1000, 5000)
        expect(query.to_sql).to include("amount")
      end
    end

    describe ".uncategorized" do
      it "returns expenses without category" do
        query = described_class.uncategorized
        expect(query.to_sql).to include('"expenses"."category_id" IS NULL')
      end
    end

    context "date-based scopes" do
      before { allow(Date).to receive(:current).and_return(Date.new(2025, 1, 15)) }

      it "filters by time periods using transaction_date" do
        %i[this_month this_year].each do |scope|
          query = described_class.send(scope)
          expect(query.to_sql).to include("transaction_date")
        end
      end
    end
  end

  describe "instance methods" do
    describe "#formatted_amount" do
      it "formats currencies correctly" do
        currency_tests = [
          [ :crc, 25000, "₡25000.0" ],
          [ :usd, 100.50, "$100.5" ],
          [ :eur, 75.25, "€75.25" ]
        ]

        currency_tests.each do |currency, amount, expected|
          expense.currency = currency
          expense.amount = amount
          expect(expense.formatted_amount).to eq(expected)
        end
      end

      it "rounds to 2 decimal places" do
        expense.amount = 123.456
        expect(expense.formatted_amount).to eq("₡123.46")
      end
    end

    describe "#bank_name" do
      it "returns email account bank name" do
        expect(expense.bank_name).to eq("BCR")
      end
    end

    describe "#category_name" do
      it "returns category name when present" do
        expect(expense.category_name).to eq("Food")
      end

      it "returns 'Uncategorized' when category is nil" do
        expense.category = nil
        expect(expense.category_name).to eq("Uncategorized")
      end
    end

    describe "#display_description" do
      it "returns description when present" do
        expense.description = "Grocery shopping"
        expense.merchant_name = "Store"
        expect(expense.display_description).to eq("Grocery shopping")
      end

      it "returns merchant_name when description is blank" do
        expense.description = ""
        expense.merchant_name = "Super ABC"
        expect(expense.display_description).to eq("Super ABC")
      end

      it "returns 'Unknown Transaction' when both are blank" do
        expense.description = nil
        expense.merchant_name = nil
        expense.merchant_normalized = nil
        expect(expense.display_description).to eq("Unknown Transaction")
      end
    end

    describe "#merchant_name" do
      it "returns merchant_name when present" do
        expense[:merchant_name] = "Store ABC"
        expense[:merchant_normalized] = "store abc"
        expect(expense.merchant_name).to eq("Store ABC")
      end

      it "returns merchant_normalized when merchant_name is nil" do
        expense[:merchant_name] = nil
        expense[:merchant_normalized] = "store abc"
        expect(expense.merchant_name).to eq("store abc")
      end

      it "returns nil when both are nil" do
        expense[:merchant_name] = nil
        expense[:merchant_normalized] = nil
        expect(expense.merchant_name).to be_nil
      end
    end

    describe "#parsed_email_data" do
      it "handles JSON parsing with fallbacks" do
        test_cases = [
          [ '{"key": "value"}', { "key" => "value" } ],
          [ "invalid json", {} ],
          [ nil, {} ]
        ]

        test_cases.each do |input, expected|
          expense.parsed_data = input
          expect(expense.parsed_email_data).to eq(expected)
        end
      end
    end

    describe "#parsed_email_data=" do
      it "converts hash to JSON" do
        expense.parsed_email_data = { key: "value" }
        expect(expense.parsed_data).to eq('{"key":"value"}')
      end
    end

    describe "status check methods" do
      it "provides accurate status predicates" do
        status_tests = [
          [ :duplicate, :duplicate? ],
          [ :processed, :processed? ],
          [ :pending, :pending? ],
          [ :failed, :failed? ]
        ]

        status_tests.each do |status, predicate_method|
          expense.status = status
          expect(expense.send(predicate_method)).to be true

          # Test that other status methods return false
          other_methods = status_tests.map(&:last) - [ predicate_method ]
          other_methods.each do |other_method|
            expect(expense.send(other_method)).to be false
          end
        end
      end
    end

    describe "ML confidence methods" do
      describe "#confidence_level" do
        it "categorizes confidence levels correctly" do
          confidence_tests = [
            [ nil, :none ],
            [ 0.85, :high ],
            [ 0.70, :medium ],
            [ 0.50, :low ],
            [ 0.30, :very_low ]
          ]

          confidence_tests.each do |confidence, expected_level|
            expense.ml_confidence = confidence
            expect(expense.confidence_level).to eq(expected_level)
          end
        end
      end

      describe "#confidence_percentage" do
        it "converts confidence to percentage" do
          percentage_tests = [
            [ nil, 0 ],
            [ 0.856, 86 ]
          ]

          percentage_tests.each do |confidence, expected_percentage|
            expense.ml_confidence = confidence
            expect(expense.confidence_percentage).to eq(expected_percentage)
          end
        end
      end

      describe "#needs_review?" do
        it "returns true for low confidence" do
          expense.ml_confidence = 0.55
          expect(expense.needs_review?).to be true
        end

        it "returns true for very low confidence" do
          expense.ml_confidence = 0.30
          expect(expense.needs_review?).to be true
        end

        it "returns false for medium confidence" do
          expense.ml_confidence = 0.75
          expect(expense.needs_review?).to be false
        end

        it "returns false for high confidence" do
          expense.ml_confidence = 0.90
          expect(expense.needs_review?).to be false
        end
      end
    end

    describe "#locked?" do
      it "returns false (placeholder implementation)" do
        expect(expense.locked?).to be false
      end
    end

    describe "#accept_ml_suggestion!" do
      let(:expense) { create(:expense, email_account: real_email_account) }

      before do
        expense.ml_suggested_category_id = real_ml_category.id
        expense.ml_correction_count = 2
      end

      it "applies the ML suggestion" do
        expense.accept_ml_suggestion!

        expect(expense.category_id).to eq(real_ml_category.id)
        expect(expense.ml_suggested_category_id).to be_nil
      end

      it "updates confidence to 1.0" do
        expense.accept_ml_suggestion!

        expect(expense.ml_confidence).to eq(1.0)
        expect(expense.ml_confidence_explanation).to eq("Manually confirmed by user")
      end

      it "increments correction count" do
        expense.accept_ml_suggestion!
        expect(expense.ml_correction_count).to eq(3)
      end

      it "sets last corrected timestamp" do
        freeze_time do
          expense.accept_ml_suggestion!
          expect(expense.ml_last_corrected_at).to eq(Time.current)
        end
      end

      it "returns false when no suggestion present" do
        expense.ml_suggested_category_id = nil
        expect(expense.accept_ml_suggestion!).to be false
      end

      it "uses transaction for atomicity" do
        expect(expense).to receive(:transaction).and_yield
        expense.accept_ml_suggestion!
      end
    end

    describe "#reject_ml_suggestion!" do
      let(:expense) { create(:expense, email_account: real_email_account, category: real_category) }
      let(:new_category) { create(:category, name: "New Category") }

      before do
        expense.ml_suggested_category_id = real_ml_category.id
        expense.ml_correction_count = 1
      end

      it "applies the new category" do
        expense.reject_ml_suggestion!(new_category.id)

        expect(expense.category_id).to eq(new_category.id)
        expect(expense.ml_suggested_category_id).to be_nil
      end

      it "updates confidence to 1.0" do
        expense.reject_ml_suggestion!(new_category.id)

        expect(expense.ml_confidence).to eq(1.0)
        expect(expense.ml_confidence_explanation).to eq("Manually corrected by user")
      end

      it "increments correction count" do
        expense.reject_ml_suggestion!(new_category.id)
        expect(expense.ml_correction_count).to eq(2)
      end

      it "creates learning event" do
        expect {
          expense.reject_ml_suggestion!(new_category.id)
        }.to change(PatternLearningEvent, :count).by(1)

        event = PatternLearningEvent.last
        expect(event.category_id).to eq(new_category.id)
        expect(event.pattern_used).to eq("manual_correction")
        expect(event.was_correct).to be true
      end

      it "uses transaction for atomicity" do
        expect(expense).to receive(:transaction).and_yield
        allow(expense.pattern_learning_events).to receive(:create!)
        expense.reject_ml_suggestion!(new_category.id)
      end
    end
  end

  describe "class methods" do
    describe ".total_amount_for_period" do
      it "calculates total for date range" do
        start_date = Date.new(2025, 1, 1)
        end_date = Date.new(2025, 1, 31)

        relation = double("relation")
        expect(described_class).to receive(:by_date_range).with(start_date, end_date).and_return(relation)
        expect(relation).to receive(:sum).with(:amount).and_return(150000)

        result = described_class.total_amount_for_period(start_date, end_date)
        expect(result).to eq(150000)
      end
    end

    describe ".by_category_summary" do
      it "groups expenses by category name" do
        relation = double("relation")
        grouped = double("grouped")

        expect(described_class).to receive(:joins).with(:category).and_return(relation)
        expect(relation).to receive(:group).with("categories.name").and_return(grouped)
        expect(grouped).to receive(:sum).with(:amount).and_return({
          "Food" => 50000,
          nil => 10000
        })

        result = described_class.by_category_summary
        expect(result).to eq({
          "Food" => 50000,
          "Uncategorized" => 10000
        })
      end
    end

    describe ".monthly_summary" do
      it "groups by month for last 12 months" do
        relation = double("relation")
        expect(described_class).to receive(:group_by_month).with(:transaction_date, last: 12).and_return(relation)
        expect(relation).to receive(:sum).with(:amount).and_return({})

        described_class.monthly_summary
      end
    end
  end

  describe "private methods" do
    describe "#normalize_merchant_name" do
      it "normalizes merchant name correctly" do
        expense.merchant_name = "  SUPER-ABC!!!  "
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("super abc")
      end

      it "removes special characters" do
        expense.merchant_name = "Store@#$%ABC"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("store abc")
      end

      it "compresses multiple spaces" do
        expense.merchant_name = "Store    ABC"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("store abc")
      end

      it "handles nil merchant name" do
        expense.merchant_name = nil
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to be_nil
      end

      it "only updates when value changes" do
        expense.merchant_name = "Store ABC"
        expense.merchant_normalized = "store abc"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("store abc")
      end
    end

    describe "#trigger_metrics_refresh" do
      let(:expense) { create(:expense, email_account: real_email_account) }

      it "triggers refresh for amount change" do
        expense.amount = 10000
        expense.save!

        expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
          expense.email_account_id,
          hash_including(affected_date: expense.transaction_date)
        )

        expense.send(:trigger_metrics_refresh)
      end

      it "triggers refresh for both old and new dates on date change" do
        old_date = expense.transaction_date
        expense.transaction_date = 1.day.from_now
        expense.save!

        expect(MetricsRefreshJob).to receive(:enqueue_debounced).twice
        expense.send(:trigger_metrics_refresh)
      end

      it "handles exceptions gracefully" do
        allow(MetricsRefreshJob).to receive(:enqueue_debounced).and_raise(StandardError)
        expect(Rails.logger).to receive(:error).at_least(:once)

        expect { expense.send(:trigger_metrics_refresh) }.not_to raise_error
      end

      it "does not trigger for insignificant changes" do
        expense.description = "Updated description"
        expense.save!

        expect(MetricsRefreshJob).not_to receive(:enqueue_debounced)
        expense.send(:trigger_metrics_refresh)
      end
    end
  end

  describe "edge cases and error conditions" do
    # Use an expense without category for edge case tests that don't need category validation
    let(:edge_case_expense) do
      build(:expense,
        email_account: email_account,
        category: nil,  # No category for edge case tests
        amount: 25000.0,
        currency: :crc,
        transaction_date: Date.current,
        status: :processed,
        merchant_name: "Super ABC",
        merchant_normalized: "super abc",
        description: "Purchase at Super ABC")
    end

    describe "amount edge cases" do
      it "handles very large amounts" do
        edge_case_expense.amount = 999_999_999_999.99
        expect(edge_case_expense).to be_valid
      end

      it "handles very small positive amounts" do
        edge_case_expense.amount = 0.01
        expect(edge_case_expense).to be_valid
      end
    end

    describe "date edge cases" do
      it "handles far future dates" do
        edge_case_expense.transaction_date = Date.new(2100, 1, 1)
        expect(edge_case_expense).to be_valid
      end

      it "handles far past dates" do
        edge_case_expense.transaction_date = Date.new(1900, 1, 1)
        expect(edge_case_expense).to be_valid
      end
    end

    describe "JSON parsing edge cases" do
      it "handles malformed JSON gracefully" do
        expense.parsed_data = "{invalid json"
        expect(expense.parsed_email_data).to eq({})
      end

      it "handles deeply nested JSON" do
        nested_data = { level1: { level2: { level3: "value" } } }
        expense.parsed_email_data = nested_data
        parsed = expense.parsed_email_data
        expect(parsed["level1"]["level2"]["level3"]).to eq("value")
      end
    end

    describe "merchant normalization edge cases" do
      it "handles unicode characters" do
        expense.merchant_name = "Café Niño"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("caf ni o")
      end

      it "handles emojis" do
        expense.merchant_name = "Store 🏪"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("store")
      end

      it "handles only special characters" do
        expense.merchant_name = "@#$%"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("")
      end
    end

    describe "concurrent update scenarios" do
      it "handles race conditions in ML suggestion acceptance" do
        expense = create(:expense, email_account: real_email_account)
        expense.ml_suggested_category_id = real_ml_category.id

        # Simulate concurrent update
        expect(expense).to receive(:transaction).and_yield
        expense.accept_ml_suggestion!
      end
    end
  end

  describe "performance considerations" do
    describe "query optimization" do
      it "uses indexed columns in scopes" do
        # Verify scopes use indexed columns
        expect(described_class.by_status("processed").to_sql).to include("status")
        expect(described_class.uncategorized.to_sql).to include("category_id")
        expect(described_class.recent.to_sql).to include("transaction_date")
      end
    end

    describe "callback optimization" do
      it "debounces metrics refresh" do
        expense = create(:expense, email_account: real_email_account)

        expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
          anything,
          hash_including(delay: 3.seconds)
        )

        expense.update!(amount: 10000)
      end

      it "only refreshes for significant changes" do
        expense = create(:expense, email_account: real_email_account)

        # Description change should not trigger refresh
        expect(MetricsRefreshJob).not_to receive(:enqueue_debounced)
        expense.update!(description: "New description")
      end
    end
  end

  describe "security considerations" do
    describe "input sanitization" do
      # Use an expense without category for security tests
      let(:security_test_expense) do
        build(:expense,
          email_account: email_account,
          category: nil,  # No category for security tests
          amount: 25000.0,
          currency: :crc,
          transaction_date: Date.current,
          status: :processed,
          merchant_name: "Super ABC",
          merchant_normalized: "super abc",
          description: "Purchase at Super ABC")
      end

      it "accepts but does not execute script tags in description" do
        security_test_expense.description = "<script>alert('XSS')</script>"
        expect(security_test_expense).to be_valid
        expect(security_test_expense.description).to eq("<script>alert('XSS')</script>")
      end

      it "handles SQL injection attempts in merchant_name" do
        security_test_expense.merchant_name = "'; DROP TABLE expenses; --"
        security_test_expense.send(:normalize_merchant_name)
        expect(security_test_expense.merchant_normalized).to eq("drop table expenses")
      end
    end

    describe "data isolation" do
      it "scopes to email_account through association" do
        expect(expense.email_account).to eq(email_account)
        expect(expense.email_account_id).to eq(email_account.id)
      end
    end
  end
end
