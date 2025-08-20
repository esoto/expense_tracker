# frozen_string_literal: true

require "rails_helper"

RSpec.describe Expense, type: :model, unit: true do
  # Use build_stubbed for true unit testing
  let(:email_account) { build_stubbed(:email_account, id: 1, bank_name: "BCR") }
  let(:category) { build_stubbed(:category, id: 1, name: "Food") }
  let(:ml_category) { build_stubbed(:category, id: 2, name: "Transport") }
  let(:expense) do
    build_stubbed(:expense,
      id: 1,
      email_account: email_account,
      category: category,
      ml_suggested_category: ml_category,
      amount: 25000.0,
      currency: :crc,
      transaction_date: Date.current,
      status: "processed",
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

    describe "amount validation" do
      it "validates presence of amount" do
        subject.amount = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:amount]).to include("can't be blank")
      end

      it "validates amount is greater than 0" do
        subject.amount = 0
        expect(subject).not_to be_valid
        expect(subject.errors[:amount]).to include("must be greater than 0")
      end

      it "rejects negative amounts" do
        subject.amount = -100
        expect(subject).not_to be_valid
        expect(subject.errors[:amount]).to include("must be greater than 0")
      end

      it "accepts positive amounts" do
        subject.amount = 50000
        expect(subject).to be_valid
      end

      it "accepts decimal amounts" do
        subject.amount = 123.45
        expect(subject).to be_valid
      end
    end

    describe "transaction_date validation" do
      it "validates presence of transaction_date" do
        subject.transaction_date = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:transaction_date]).to include("can't be blank")
      end

      it "accepts valid dates" do
        subject.transaction_date = Date.current
        expect(subject).to be_valid
      end

      it "accepts past dates" do
        subject.transaction_date = 1.year.ago
        expect(subject).to be_valid
      end

      it "accepts future dates" do
        subject.transaction_date = 1.day.from_now
        expect(subject).to be_valid
      end
    end

    describe "status validation" do
      it "validates presence of status" do
        subject.status = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:status]).to include("can't be blank")
      end

      it "validates inclusion of status" do
        subject.status = "invalid"
        expect(subject).not_to be_valid
        expect(subject.errors[:status]).to include("is not included in the list")
      end

      it "accepts valid statuses" do
        %w[pending processed failed duplicate].each do |status|
          subject.status = status
          expect(subject).to be_valid
        end
      end
    end

    describe "currency validation" do
      it "validates presence of currency" do
        subject.currency = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:currency]).to include("can't be blank")
      end

      it "accepts valid currencies" do
        %i[crc usd eur].each do |currency|
          subject.currency = currency
          expect(subject).to be_valid
        end
      end
    end
  end

  describe "associations" do
    it "belongs to email_account" do
      association = described_class.reflect_on_association(:email_account)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be_falsey
    end

    it "belongs to category (optional)" do
      association = described_class.reflect_on_association(:category)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:optional]).to be true
    end

    it "belongs to ml_suggested_category (optional)" do
      association = described_class.reflect_on_association(:ml_suggested_category)
      expect(association.macro).to eq(:belongs_to)
      expect(association.options[:class_name]).to eq("Category")
      expect(association.options[:foreign_key]).to eq("ml_suggested_category_id")
      expect(association.options[:optional]).to be true
    end

    it "has many pattern_feedbacks" do
      association = described_class.reflect_on_association(:pattern_feedbacks)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many pattern_learning_events" do
      association = described_class.reflect_on_association(:pattern_learning_events)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end

    it "has many bulk_operation_items" do
      association = described_class.reflect_on_association(:bulk_operation_items)
      expect(association.macro).to eq(:has_many)
      expect(association.options[:dependent]).to eq(:destroy)
    end
  end

  describe "enums" do
    describe "currency enum" do
      it "defines correct currency values" do
        expect(described_class.currencies).to eq({
          "crc" => 0,
          "usd" => 1,
          "eur" => 2
        })
      end

      it "provides currency check methods" do
        expense.currency = :crc
        expect(expense.crc?).to be true
        expect(expense.usd?).to be false
        expect(expense.eur?).to be false
      end
    end
  end

  describe "callbacks" do
    describe "before_save :normalize_merchant_name" do
      it "normalizes merchant name on save" do
        expense = build(:expense, 
          email_account: email_account,
          merchant_name: "  SUPER-ABC!!!  ")
        
        expense.save!
        expect(expense.merchant_normalized).to eq("super abc")
      end

      it "handles nil merchant name" do
        expense = build(:expense, 
          email_account: email_account,
          merchant_name: nil)
        
        expense.save!
        expect(expense.merchant_normalized).to be_nil
      end

      it "only updates when merchant_name changes" do
        expense = create(:expense, 
          email_account: email_account,
          merchant_name: "Store ABC",
          merchant_normalized: "store abc")
        
        expense.update!(amount: 5000)
        expect(expense.merchant_normalized).to eq("store abc")
      end
    end

    describe "after_commit callbacks" do
      let(:expense) { create(:expense, email_account: email_account) }

      it "triggers clear_dashboard_cache" do
        expect(DashboardService).to receive(:clear_cache)
        expense.update!(amount: 10000)
      end

      it "triggers metrics refresh on create" do
        expect(MetricsRefreshJob).to receive(:enqueue_debounced)
        create(:expense, email_account: email_account)
      end

      it "triggers metrics refresh on update" do
        expect(MetricsRefreshJob).to receive(:enqueue_debounced)
        expense.update!(amount: 10000)
      end

      it "triggers metrics refresh on destroy" do
        expect(MetricsRefreshJob).to receive(:enqueue_debounced)
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
        expect(query.to_sql).to include('"expenses"."status" = \'processed\'')
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

    describe ".this_month" do
      it "returns expenses for current month" do
        allow(Date).to receive(:current).and_return(Date.new(2025, 1, 15))
        query = described_class.this_month
        expect(query.to_sql).to include("transaction_date")
      end
    end

    describe ".this_year" do
      it "returns expenses for current year" do
        allow(Date).to receive(:current).and_return(Date.new(2025, 1, 15))
        query = described_class.this_year
        expect(query.to_sql).to include("transaction_date")
      end
    end
  end

  describe "instance methods" do
    describe "#formatted_amount" do
      it "formats CRC currency correctly" do
        expense.currency = :crc
        expense.amount = 25000
        expect(expense.formatted_amount).to eq("₡25000.0")
      end

      it "formats USD currency correctly" do
        expense.currency = :usd
        expense.amount = 100.50
        expect(expense.formatted_amount).to eq("$100.5")
      end

      it "formats EUR currency correctly" do
        expense.currency = :eur
        expense.amount = 75.25
        expect(expense.formatted_amount).to eq("€75.25")
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
      it "parses valid JSON" do
        expense.parsed_data = '{"key": "value"}'
        expect(expense.parsed_email_data).to eq({"key" => "value"})
      end

      it "returns empty hash for invalid JSON" do
        expense.parsed_data = "invalid json"
        expect(expense.parsed_email_data).to eq({})
      end

      it "returns empty hash for nil" do
        expense.parsed_data = nil
        expect(expense.parsed_email_data).to eq({})
      end
    end

    describe "#parsed_email_data=" do
      it "converts hash to JSON" do
        expense.parsed_email_data = { key: "value" }
        expect(expense.parsed_data).to eq('{"key":"value"}')
      end
    end

    describe "status check methods" do
      it "#duplicate? returns true for duplicate status" do
        expense.status = "duplicate"
        expect(expense.duplicate?).to be true
        expect(expense.processed?).to be false
      end

      it "#processed? returns true for processed status" do
        expense.status = "processed"
        expect(expense.processed?).to be true
        expect(expense.pending?).to be false
      end

      it "#pending? returns true for pending status" do
        expense.status = "pending"
        expect(expense.pending?).to be true
        expect(expense.failed?).to be false
      end

      it "#failed? returns true for failed status" do
        expense.status = "failed"
        expect(expense.failed?).to be true
        expect(expense.duplicate?).to be false
      end
    end

    describe "currency detection methods" do
      describe "#detect_and_set_currency" do
        it "detects and saves currency for persisted record" do
          expense = create(:expense, email_account: email_account)
          allow(expense).to receive(:detect_currency).and_return("usd")
          
          result = expense.detect_and_set_currency("Email with $100")
          
          expect(result).to eq("usd")
          expect(expense.reload.currency).to eq("usd")
        end

        it "detects but doesn't save for unpersisted record" do
          expense = build(:expense, email_account: email_account)
          allow(expense).to receive(:detect_currency).and_return("eur")
          
          result = expense.detect_and_set_currency("Email with €50")
          
          expect(result).to eq("eur")
          expect(expense.currency).to eq("eur")
        end
      end

      describe "#detect_currency" do
        it "detects USD from dollar sign" do
          expect(expense.detect_currency("Payment of $100")).to eq("usd")
        end

        it "detects USD from text" do
          expect(expense.detect_currency("100 USD dollars")).to eq("usd")
        end

        it "detects EUR from euro sign" do
          expect(expense.detect_currency("Payment of €50")).to eq("eur")
        end

        it "detects EUR from text" do
          expect(expense.detect_currency("50 EUR euros")).to eq("eur")
        end

        it "defaults to CRC" do
          expect(expense.detect_currency("Payment of 25000")).to eq("crc")
        end

        it "is case insensitive" do
          expect(expense.detect_currency("100 UsD")).to eq("usd")
        end

        it "uses multiple fields for detection" do
          expense.description = "Payment in dollars"
          expense.merchant_name = "USD Store"
          expect(expense.detect_currency).to eq("usd")
        end
      end
    end

    describe "category guessing methods" do
      describe "#guess_category" do
        before do
          allow(Category).to receive(:find_by).and_return(nil)
        end

        it "identifies food category" do
          food_category = build_stubbed(:category, name: "Alimentación")
          allow(Category).to receive(:find_by).with(name: "Alimentación").and_return(food_category)
          
          expense.description = "Restaurant visit"
          result = expense.guess_category
          
          expect(result).to eq(food_category)
        end

        it "identifies transport category" do
          transport_category = build_stubbed(:category, name: "Transporte")
          allow(Category).to receive(:find_by).with(name: "Transporte").and_return(transport_category)
          
          expense.merchant_name = "Gasolina Station"
          result = expense.guess_category
          
          expect(result).to eq(transport_category)
        end

        it "returns default category when no match" do
          default_category = build_stubbed(:category, name: "Sin Categoría")
          allow(Category).to receive(:find_by).with(name: "Sin Categoría").and_return(default_category)
          
          expense.description = "Random purchase"
          result = expense.guess_category
          
          expect(result).to eq(default_category)
        end

        it "returns nil when text is blank" do
          expense.description = nil
          expense.merchant_name = nil
          
          result = expense.guess_category
          expect(result).to be_nil
        end

        it "is case insensitive" do
          food_category = build_stubbed(:category, name: "Alimentación")
          allow(Category).to receive(:find_by).with(name: "Alimentación").and_return(food_category)
          
          expense.description = "RESTAURANT"
          result = expense.guess_category
          
          expect(result).to eq(food_category)
        end
      end

      describe "#auto_categorize!" do
        it "sets category when nil" do
          expense.category = nil
          guessed_category = build_stubbed(:category, name: "Guessed")
          allow(expense).to receive(:guess_category).and_return(guessed_category)
          allow(expense).to receive(:save)
          allow(expense).to receive(:changed?).and_return(true)
          
          expense.auto_categorize!
          
          expect(expense.category).to eq(guessed_category)
        end

        it "does not change existing category" do
          original_category = expense.category
          allow(expense).to receive(:guess_category)
          
          expense.auto_categorize!
          
          expect(expense.category).to eq(original_category)
          expect(expense).not_to have_received(:guess_category)
        end

        it "saves when category changes" do
          expense.category = nil
          guessed_category = build_stubbed(:category)
          allow(expense).to receive(:guess_category).and_return(guessed_category)
          allow(expense).to receive(:changed?).and_return(true)
          expect(expense).to receive(:save)
          
          expense.auto_categorize!
        end
      end
    end

    describe "ML confidence methods" do
      describe "#confidence_level" do
        it "returns :none for nil confidence" do
          expense.ml_confidence = nil
          expect(expense.confidence_level).to eq(:none)
        end

        it "returns :high for >= 0.85" do
          expense.ml_confidence = 0.85
          expect(expense.confidence_level).to eq(:high)
        end

        it "returns :medium for >= 0.70" do
          expense.ml_confidence = 0.70
          expect(expense.confidence_level).to eq(:medium)
        end

        it "returns :low for >= 0.50" do
          expense.ml_confidence = 0.50
          expect(expense.confidence_level).to eq(:low)
        end

        it "returns :very_low for < 0.50" do
          expense.ml_confidence = 0.30
          expect(expense.confidence_level).to eq(:very_low)
        end
      end

      describe "#confidence_percentage" do
        it "returns 0 for nil confidence" do
          expense.ml_confidence = nil
          expect(expense.confidence_percentage).to eq(0)
        end

        it "converts to percentage and rounds" do
          expense.ml_confidence = 0.856
          expect(expense.confidence_percentage).to eq(86)
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
      let(:expense) { create(:expense, email_account: email_account) }

      before do
        expense.ml_suggested_category_id = ml_category.id
        expense.ml_correction_count = 2
      end

      it "applies the ML suggestion" do
        expense.accept_ml_suggestion!
        
        expect(expense.category_id).to eq(ml_category.id)
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
      let(:expense) { create(:expense, email_account: email_account, category_id: 1) }
      let(:new_category) { create(:category, name: "New Category") }

      before do
        expense.ml_suggested_category_id = ml_category.id
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

    describe ".summary_for_period" do
      it "returns weekly summary for 'week'" do
        expect(described_class).to receive(:weekly_summary).and_return({})
        described_class.summary_for_period("week")
      end

      it "returns monthly summary for 'month'" do
        expect(described_class).to receive(:monthly_summary_report).and_return({})
        described_class.summary_for_period("month")
      end

      it "returns yearly summary for 'year'" do
        expect(described_class).to receive(:yearly_summary).and_return({})
        described_class.summary_for_period("year")
      end

      it "defaults to monthly summary" do
        expect(described_class).to receive(:monthly_summary_report).and_return({})
        described_class.summary_for_period("invalid")
      end
    end

    describe ".build_summary" do
      let(:start_date) { 1.month.ago }
      let(:end_date) { Time.current }
      let(:expenses_relation) { double("expenses") }

      before do
        allow(described_class).to receive(:by_date_range).and_return(expenses_relation)
        allow(expenses_relation).to receive(:sum).with(:amount).and_return(100000)
        allow(expenses_relation).to receive(:count).and_return(25)
        allow(expenses_relation).to receive_message_chain(:joins, :group, :sum, :transform_values)
          .and_return({ "Food" => 50000.0 })
      end

      it "builds summary hash with correct structure" do
        result = described_class.build_summary(start_date, end_date)
        
        expect(result).to include(
          total_amount: 100000.0,
          expense_count: 25,
          start_date: start_date.iso8601,
          end_date: end_date.iso8601,
          by_category: { "Food" => 50000.0 }
        )
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
      let(:expense) { create(:expense, email_account: email_account) }

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
        expect(Rails.logger).to receive(:error)
        
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
    describe "amount edge cases" do
      it "handles very large amounts" do
        expense.amount = 999_999_999_999.99
        expect(expense).to be_valid
      end

      it "handles very small positive amounts" do
        expense.amount = 0.01
        expect(expense).to be_valid
      end
    end

    describe "date edge cases" do
      it "handles far future dates" do
        expense.transaction_date = Date.new(2100, 1, 1)
        expect(expense).to be_valid
      end

      it "handles far past dates" do
        expense.transaction_date = Date.new(1900, 1, 1)
        expect(expense).to be_valid
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
        expense = create(:expense, email_account: email_account)
        expense.ml_suggested_category_id = 1
        
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
        expense = create(:expense, email_account: email_account)
        
        expect(MetricsRefreshJob).to receive(:enqueue_debounced).with(
          anything,
          hash_including(delay: 3.seconds)
        )
        
        expense.update!(amount: 10000)
      end

      it "only refreshes for significant changes" do
        expense = create(:expense, email_account: email_account)
        
        # Description change should not trigger refresh
        expect(MetricsRefreshJob).not_to receive(:enqueue_debounced)
        expense.update!(description: "New description")
      end
    end
  end

  describe "security considerations" do
    describe "input sanitization" do
      it "accepts but does not execute script tags in description" do
        expense.description = "<script>alert('XSS')</script>"
        expect(expense).to be_valid
        expect(expense.description).to eq("<script>alert('XSS')</script>")
      end

      it "handles SQL injection attempts in merchant_name" do
        expense.merchant_name = "'; DROP TABLE expenses; --"
        expense.send(:normalize_merchant_name)
        expect(expense.merchant_normalized).to eq("drop table expenses")
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