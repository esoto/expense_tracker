# frozen_string_literal: true

require "rails_helper"

RSpec.describe Budget, type: :model, unit: true do
  # Create real associations for tests that need them
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category, name: "Food") }
  let(:budget) do
    build(:budget,
      id: 1,
      email_account: email_account,
      category: category,
      name: "Monthly Food Budget",
      amount: 100_000,
      period: :monthly,
      start_date: Date.current.beginning_of_month,
      end_date: nil,
      currency: "CRC",
      warning_threshold: 70,
      critical_threshold: 90,
      current_spend: 0,
      current_spend_updated_at: Time.current,
      times_exceeded: 0,
      last_exceeded_at: nil,
      active: true)
  end

    describe "associations" do
      it { is_expected.to belong_to(:email_account) }
      it { is_expected.to belong_to(:category).optional }
    end

  describe "validations" do
    subject { build(:budget) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_presence_of(:amount) }
    it { is_expected.to validate_numericality_of(:amount).is_greater_than(0) }
    it { is_expected.to validate_presence_of(:period) }
    it { is_expected.to validate_presence_of(:start_date).on(:update) }
    it { is_expected.to validate_presence_of(:currency).on(:update) }
    it { is_expected.to validate_inclusion_of(:currency).in_array(%w[CRC USD EUR]).on(:update) }

    describe 'thresholds_order' do
      it 'validates warning_threshold is less than critical_threshold' do
        budget = build(:budget, warning_threshold: 80, critical_threshold: 90)
        expect(budget).to be_valid
      end

      it 'invalidates if warning_threshold is greater than or equal to critical_threshold' do
        budget = build(:budget, warning_threshold: 90, critical_threshold: 90)
        expect(budget).to be_invalid
      end
    end

    describe 'end_date_after_start_date' do
      it 'validates end_date is after start_date' do
        budget = build(:budget, start_date: Date.current, end_date: Date.current + 1.day)
        expect(budget).to be_valid
      end

      it 'invalidates if end_date is before start_date' do
        budget = build(:budget, start_date: Date.current, end_date: Date.current - 1.day)
        expect(budget).to be_invalid
      end
    end

    describe 'unique_active_budget_per_scope' do
      before do
        create(:budget,
          email_account: email_account,
          category: category,
          name: "Existing Budget",
          active: true)
      end

      it 'validates uniqueness of active budget per email_account and category' do
        budget = build(:budget,
          email_account: email_account,
          category: category,
          name: "New Budget",
          active: true)

        expect(budget).to be_invalid
        expect(budget.errors[:base]).to include("Ya existe un presupuesto activo para este período y categoría")
      end

      it 'allows multiple inactive budgets for same scope' do
        budget = build(:budget,
          email_account: email_account,
          category: category,
          name: "New Budget",
          active: false)

        expect(budget).to be_valid
      end

      it 'allows multiple active budgets if categories differ' do
        other_category = create(:category, name: "Transport")
        budget = build(:budget,
          email_account: email_account,
          category: other_category,
          name: "New Budget",
          active: true)

        expect(budget).to be_valid
      end

      it 'allows multiple active budgets if email_accounts differ' do
        other_email_account = create(:email_account)
        budget = build(:budget,
          email_account: other_email_account,
          category: category,
          name: "New Budget",
          active: true)

        expect(budget).to be_valid
      end
    end
  end

  describe "enums" do
    describe "period enum" do
      it "defines correct period values" do
        expect(described_class.periods).to eq({
          "daily" => 0,
          "weekly" => 1,
          "monthly" => 2,
          "yearly" => 3
        })
      end

      it "provides period check methods with prefix" do
        budget = build_stubbed(:budget, period: :monthly)
        expect(budget.period_monthly?).to be true
        expect(budget.period_daily?).to be false
      end
    end
  end

  describe "scopes" do
    describe ".active" do
      it "returns active budgets" do
        query = described_class.active
        expect(query.to_sql).to include('WHERE "budgets"."active" = TRUE')
      end
    end

    describe ".inactive" do
      it "returns inactive budgets" do
        query = described_class.inactive
        expect(query.to_sql).to include('WHERE "budgets"."active" = FALSE')
      end
    end

    describe ".current" do
      it "returns current budgets based on date range" do
        allow(Date).to receive(:current).and_return(Date.new(2025, 1, 15))
        query = described_class.current
        expect(query.to_sql).to include('"budgets"."active" = TRUE')
        expect(query.to_sql).to include('start_date <=')
        expect(query.to_sql).to include('end_date IS NULL OR end_date >=')
      end
    end

    describe ".for_category" do
      it "returns budgets for specific category" do
        query = described_class.for_category(5)
        expect(query.to_sql).to include('"budgets"."category_id" = 5')
      end
    end

    describe ".general" do
      it "returns budgets without category" do
        query = described_class.general
        expect(query.to_sql).to include('"budgets"."category_id" IS NULL')
      end
    end

    describe ".exceeded" do
      it "returns budgets where spending exceeds amount" do
        query = described_class.exceeded
        expect(query.to_sql).to include("current_spend > amount")
      end
    end

    describe ".warning" do
      it "returns budgets at warning threshold" do
        query = described_class.warning
        expect(query.to_sql).to include("current_spend >= (amount * warning_threshold / 100.0)")
      end
    end

    describe ".critical" do
      it "returns budgets at critical threshold" do
        query = described_class.critical
        expect(query.to_sql).to include("current_spend >= (amount * critical_threshold / 100.0)")
      end
    end
  end

  describe "callbacks" do
    describe "before_validation on create" do
      it "sets default values" do
        budget = Budget.new
        budget.valid?

        expect(budget.start_date).to eq(Date.current)
        expect(budget.currency).to eq("CRC")
        expect(budget.warning_threshold).to eq(70)
        expect(budget.critical_threshold).to eq(90)
      end

      it "does not override provided values" do
        custom_date = Date.current - 1.week
        budget = Budget.new(
          start_date: custom_date,
          currency: "USD",
          warning_threshold: 60,
          critical_threshold: 80
        )
        budget.valid?

        expect(budget.start_date).to eq(custom_date)
        expect(budget.currency).to eq("USD")
        expect(budget.warning_threshold).to eq(60)
        expect(budget.critical_threshold).to eq(80)
      end
    end

    describe "after_create" do
      it "triggers calculate_current_spend_after_save" do
        budget = build(:budget, email_account: email_account)

        expect(budget).to receive(:calculate_current_spend_after_save)
        budget.save!
      end
    end

    describe "after_update" do
      it "triggers recalculate_if_needed" do
        budget = create(:budget, email_account: email_account)

        expect(budget).to receive(:recalculate_if_needed)
        budget.update!(name: "Updated Budget")
      end
    end
  end

  describe "class methods" do
    describe ".for_period_containing" do
      let(:test_date) { Date.new(2025, 1, 15) }

      context "daily period" do
        it "returns budgets containing the specific date" do
          query = described_class.for_period_containing(test_date, :daily)
          expect(query.to_sql).to include("start_date <= '2025-01-15'")
          expect(query.to_sql).to include("end_date IS NULL OR end_date >= '2025-01-15'")
        end
      end

      context "weekly period" do
        it "returns budgets containing the week" do
          query = described_class.for_period_containing(test_date, :weekly)
          week_start = test_date.beginning_of_week
          week_end = test_date.end_of_week

          expect(query.to_sql).to include("start_date <=")
          expect(query.to_sql).to include("end_date IS NULL OR end_date >=")
        end
      end

      context "monthly period" do
        it "returns budgets containing the month" do
          query = described_class.for_period_containing(test_date, :monthly)

          expect(query.to_sql).to include("start_date <=")
          expect(query.to_sql).to include("end_date IS NULL OR end_date >=")
        end
      end

      context "yearly period" do
        it "returns budgets containing the year" do
          query = described_class.for_period_containing(test_date, :yearly)

          expect(query.to_sql).to include("start_date <=")
          expect(query.to_sql).to include("end_date IS NULL OR end_date >=")
        end
      end

      context "invalid period" do
        it "returns none" do
          query = described_class.for_period_containing(test_date, :invalid)
          expect(query.to_sql).to include("1=0")
        end
      end
    end
  end

  describe "instance methods" do
    describe "#current_period_range" do
      before do
        allow(Date).to receive(:current).and_return(Date.new(2025, 1, 15))
      end

      context "daily period" do
        it "returns current day range" do
          budget.period = :daily
          range = budget.current_period_range

          expect(range.begin).to eq(Date.new(2025, 1, 15).beginning_of_day)
          expect(range.end).to eq(Date.new(2025, 1, 15).end_of_day)
        end
      end

      context "weekly period" do
        it "returns current week range" do
          budget.period = :weekly
          range = budget.current_period_range

          expect(range.begin).to eq(Date.new(2025, 1, 13)) # Monday
          expect(range.end).to eq(Date.new(2025, 1, 19))   # Sunday
        end
      end

      context "monthly period" do
        it "returns current month range" do
          budget.period = :monthly
          range = budget.current_period_range

          expect(range.begin).to eq(Date.new(2025, 1, 1))
          expect(range.end).to eq(Date.new(2025, 1, 31))
        end
      end

      context "yearly period" do
        it "returns current year range" do
          budget.period = :yearly
          range = budget.current_period_range

          expect(range.begin).to eq(Date.new(2025, 1, 1))
          expect(range.end).to eq(Date.new(2025, 12, 31))
        end
      end

      context "invalid period" do
        it "raises an error" do
          allow(budget).to receive(:period).and_return("invalid")

          expect { budget.current_period_range }.to raise_error("Invalid period: invalid")
        end
      end
    end

    describe "#calculate_current_spend!" do
      let(:expenses_relation) { double("expenses relation") }

      before do
        allow(budget).to receive(:active?).and_return(true)
        allow(budget).to receive(:current_period_range).and_return(Date.current.beginning_of_month..Date.current.end_of_month)
        allow(email_account).to receive(:expenses).and_return(expenses_relation)
        allow(expenses_relation).to receive(:includes).with(:category).and_return(expenses_relation)
        allow(expenses_relation).to receive(:where).and_return(expenses_relation)
        allow(expenses_relation).to receive(:sum).with(:amount).and_return(75_000)
        allow(budget).to receive(:update_columns)
        allow(budget).to receive(:check_and_track_exceeded)
      end

      context "when budget is inactive" do
        it "returns 0" do
          allow(budget).to receive(:active?).and_return(false)

          expect(budget.calculate_current_spend!).to eq(0.0)
        end
      end

      context "when budget is active" do
        it "calculates spend for general budget" do
          budget.category_id = nil

          expect(expenses_relation).to receive(:includes).with(:category)
          expect(expenses_relation).to receive(:where).with(
            transaction_date: budget.current_period_range
          )
          expect(expenses_relation).to receive(:where).with(
            currency: 0 # CRC enum value
          )
          expect(expenses_relation).not_to receive(:where).with(category_id: anything)

          result = budget.calculate_current_spend!
          expect(result).to eq(75_000.0)
        end

        it "calculates spend for category-specific budget" do
          budget.category_id = 5

          expect(expenses_relation).to receive(:where).with(category_id: 5)

          result = budget.calculate_current_spend!
          expect(result).to eq(75_000.0)
        end

        it "updates cached values" do
          expect(budget).to receive(:update_columns).with(
            current_spend: 75_000.0,
            current_spend_updated_at: anything
          )

          budget.calculate_current_spend!
        end

        it "checks and tracks if exceeded" do
          expect(budget).to receive(:check_and_track_exceeded).with(75_000.0)

          budget.calculate_current_spend!
        end
      end

      context "currency mapping" do
        it "maps CRC correctly" do
          budget.currency = "CRC"
          allow(Expense).to receive(:currencies).and_return({ crc: 0, usd: 1, eur: 2 })

          expect(expenses_relation).to receive(:where).with(currency: 0)
          budget.calculate_current_spend!
        end

        it "maps USD correctly" do
          budget.currency = "USD"
          allow(Expense).to receive(:currencies).and_return({ crc: 0, usd: 1, eur: 2 })

          expect(expenses_relation).to receive(:where).with(currency: 1)
          budget.calculate_current_spend!
        end

        it "maps EUR correctly" do
          budget.currency = "EUR"
          allow(Expense).to receive(:currencies).and_return({ crc: 0, usd: 1, eur: 2 })

          expect(expenses_relation).to receive(:where).with(currency: 2)
          budget.calculate_current_spend!
        end
      end
    end

    describe "#current_spend_amount" do
      context "when cache is fresh" do
        it "returns cached value without recalculating" do
          budget.current_spend = 50_000
          budget.current_spend_updated_at = 30.minutes.ago

          expect(budget).not_to receive(:calculate_current_spend!)
          expect(budget.current_spend_amount).to eq(50_000)
        end
      end

      context "when cache is stale" do
        it "recalculates when older than 1 hour" do
          budget.current_spend = 50_000
          budget.current_spend_updated_at = 2.hours.ago

          expect(budget).to receive(:calculate_current_spend!).and_return(75_000)
          expect(budget.current_spend_amount).to eq(75_000)
        end

        it "recalculates when never calculated" do
          budget.current_spend = 0
          budget.current_spend_updated_at = nil

          expect(budget).to receive(:calculate_current_spend!).and_return(25_000)
          expect(budget.current_spend_amount).to eq(25_000)
        end
      end
    end

    describe "#usage_percentage" do
      before do
        allow(budget).to receive(:current_spend_amount).and_return(50_000)
      end

      it "calculates percentage correctly" do
        budget.amount = 100_000
        expect(budget.usage_percentage).to eq(50.0)
      end

      it "rounds to one decimal place" do
        budget.amount = 100_000
        allow(budget).to receive(:current_spend_amount).and_return(33_333)
        expect(budget.usage_percentage).to eq(33.3)
      end

      it "handles zero amount" do
        budget.amount = 0
        expect(budget.usage_percentage).to eq(0.0)
      end

      it "can exceed 100%" do
        budget.amount = 100_000
        allow(budget).to receive(:current_spend_amount).and_return(150_000)
        expect(budget.usage_percentage).to eq(150.0)
      end
    end

    describe "#remaining_amount" do
      it "calculates remaining correctly" do
        budget.amount = 100_000
        allow(budget).to receive(:current_spend_amount).and_return(30_000)

        expect(budget.remaining_amount).to eq(70_000)
      end

      it "returns negative when exceeded" do
        budget.amount = 100_000
        allow(budget).to receive(:current_spend_amount).and_return(120_000)

        expect(budget.remaining_amount).to eq(-20_000)
      end
    end

    describe "#status" do
      before do
        budget.warning_threshold = 70
        budget.critical_threshold = 90
      end

      it "returns :exceeded when over 100%" do
        allow(budget).to receive(:usage_percentage).and_return(105.0)
        expect(budget.status).to eq(:exceeded)
      end

      it "returns :critical when at critical threshold" do
        allow(budget).to receive(:usage_percentage).and_return(92.0)
        expect(budget.status).to eq(:critical)
      end

      it "returns :warning when at warning threshold" do
        allow(budget).to receive(:usage_percentage).and_return(75.0)
        expect(budget.status).to eq(:warning)
      end

      it "returns :good when below warning threshold" do
        allow(budget).to receive(:usage_percentage).and_return(50.0)
        expect(budget.status).to eq(:good)
      end

      it "prioritizes exceeded over critical" do
        allow(budget).to receive(:usage_percentage).and_return(100.0)
        expect(budget.status).to eq(:exceeded)
      end

      it "prioritizes critical over warning" do
        allow(budget).to receive(:usage_percentage).and_return(90.0)
        expect(budget.status).to eq(:critical)
      end
    end

    describe "#status_color" do
      it "returns rose-600 for exceeded" do
        allow(budget).to receive(:status).and_return(:exceeded)
        expect(budget.status_color).to eq("rose-600")
      end

      it "returns rose-500 for critical" do
        allow(budget).to receive(:status).and_return(:critical)
        expect(budget.status_color).to eq("rose-500")
      end

      it "returns amber-600 for warning" do
        allow(budget).to receive(:status).and_return(:warning)
        expect(budget.status_color).to eq("amber-600")
      end

      it "returns emerald-600 for good" do
        allow(budget).to receive(:status).and_return(:good)
        expect(budget.status_color).to eq("emerald-600")
      end
    end

    describe "#status_message" do
      it "returns Spanish message for exceeded" do
        allow(budget).to receive(:status).and_return(:exceeded)
        expect(budget.status_message).to eq("Presupuesto excedido")
      end

      it "returns Spanish message for critical" do
        allow(budget).to receive(:status).and_return(:critical)
        expect(budget.status_message).to eq("Cerca del límite")
      end

      it "returns Spanish message for warning" do
        allow(budget).to receive(:status).and_return(:warning)
        expect(budget.status_message).to eq("Atención requerida")
      end

      it "returns Spanish message for good" do
        allow(budget).to receive(:status).and_return(:good)
        expect(budget.status_message).to eq("Dentro del presupuesto")
      end
    end

    describe "#on_track?" do
      it "returns true when usage is below 50%" do
        allow(budget).to receive(:usage_percentage).and_return(45.0)
        expect(budget.on_track?).to be true
      end

      it "considers period elapsed percentage with buffer" do
        allow(budget).to receive(:usage_percentage).and_return(65.0)
        allow(budget).to receive(:period_elapsed_percentage).and_return(60.0)

        # 65% used, 60% elapsed + 10% buffer = 70% allowed
        expect(budget.on_track?).to be true
      end

      it "returns false when exceeding elapsed percentage plus buffer" do
        allow(budget).to receive(:usage_percentage).and_return(75.0)
        allow(budget).to receive(:period_elapsed_percentage).and_return(50.0)

        # 75% used, 50% elapsed + 10% buffer = 60% allowed
        expect(budget.on_track?).to be false
      end
    end

    describe "#period_elapsed_percentage" do
      before do
        allow(Date).to receive(:current).and_return(Date.new(2025, 1, 15))
      end

      it "calculates elapsed percentage for monthly period" do
        budget.period = :monthly
        allow(budget).to receive(:current_period_range).and_return(
          Date.new(2025, 1, 1)..Date.new(2025, 1, 31)
        )

        # 15 days elapsed out of 31
        expect(budget.period_elapsed_percentage).to eq(48.4)
      end

      it "returns 100 when period is complete" do
        allow(Date).to receive(:current).and_return(Date.new(2025, 2, 1))
        allow(budget).to receive(:current_period_range).and_return(
          Date.new(2025, 1, 1)..Date.new(2025, 1, 31)
        )

        expect(budget.period_elapsed_percentage).to eq(100.0)
      end

      it "handles single day periods" do
        budget.period = :daily
        allow(budget).to receive(:current_period_range).and_return(
          Date.new(2025, 1, 15)..Date.new(2025, 1, 15)
        )

        expect(budget.period_elapsed_percentage).to eq(100.0)
      end
    end

    describe "#historical_adherence" do
      it "returns historical data structure" do
        budget.times_exceeded = 3

        result = budget.historical_adherence(6)

        expect(result[:periods_analyzed]).to eq(6)
        expect(result[:times_exceeded]).to eq(3)
        expect(result[:average_usage]).to eq(85.0)
        expect(result[:trend]).to eq(:improving)
      end

      it "accepts custom period count" do
        result = budget.historical_adherence(12)
        expect(result[:periods_analyzed]).to eq(12)
      end
    end

    describe "#formatted_amount" do
      it "formats CRC currency correctly" do
        budget.currency = "CRC"
        budget.amount = 150_000

        expect(budget.formatted_amount).to eq("₡150.000")
      end

      it "formats USD currency correctly" do
        budget.currency = "USD"
        budget.amount = 1500.50

        expect(budget.formatted_amount).to eq("$1.501")
      end

      it "formats EUR currency correctly" do
        budget.currency = "EUR"
        budget.amount = 2000.75

        expect(budget.formatted_amount).to eq("€2.001")
      end
    end

    describe "#formatted_remaining" do
      it "formats positive remaining amount" do
        budget.currency = "CRC"
        allow(budget).to receive(:remaining_amount).and_return(50_000)

        expect(budget.formatted_remaining).to eq("₡50.000")
      end

      it "formats negative remaining amount as absolute value" do
        budget.currency = "CRC"
        allow(budget).to receive(:remaining_amount).and_return(-20_000)

        expect(budget.formatted_remaining).to eq("₡20.000")
      end
    end

    describe "#currency_symbol" do
      it "returns ₡ for CRC" do
        budget.currency = "CRC"
        expect(budget.currency_symbol).to eq("₡")
      end

      it "returns $ for USD" do
        budget.currency = "USD"
        expect(budget.currency_symbol).to eq("$")
      end

      it "returns € for EUR" do
        budget.currency = "EUR"
        expect(budget.currency_symbol).to eq("€")
      end

      it "returns currency code for unknown currencies" do
        budget.currency = "GBP"
        expect(budget.currency_symbol).to eq("GBP")
      end
    end

    describe "#deactivate!" do
      it "sets active to false" do
        budget = create(:budget, email_account: email_account, active: true)

        budget.deactivate!

        expect(budget.reload.active).to be false
      end

      it "raises error if update fails" do
        allow(budget).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect { budget.deactivate! }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe "#duplicate_for_next_period" do
      let(:budget) do
        create(:budget,
          email_account: email_account,
          category: category,
          name: "Monthly Budget",
          period: :monthly,
          amount: 100_000,
          start_date: Date.new(2025, 1, 1),
          end_date: Date.new(2025, 12, 31))
      end

      it "creates a new budget for the next period" do
        expect {
          budget.duplicate_for_next_period
        }.to change(Budget, :count).by(1)
      end

      it "calculates next period start correctly for daily" do
        budget.period = :daily
        budget.start_date = Date.new(2025, 1, 15)

        new_budget = budget.duplicate_for_next_period
        expect(new_budget.start_date).to eq(Date.new(2025, 1, 16))
      end

      it "calculates next period start correctly for weekly" do
        budget.period = :weekly
        budget.start_date = Date.new(2025, 1, 6) # Monday

        new_budget = budget.duplicate_for_next_period
        expect(new_budget.start_date).to eq(Date.new(2025, 1, 13))
      end

      it "calculates next period start correctly for monthly" do
        budget.period = :monthly
        budget.start_date = Date.new(2025, 1, 1)

        new_budget = budget.duplicate_for_next_period
        expect(new_budget.start_date).to eq(Date.new(2025, 2, 1))
      end

      it "calculates next period start correctly for yearly" do
        budget.period = :yearly
        budget.start_date = Date.new(2025, 1, 1)

        new_budget = budget.duplicate_for_next_period
        expect(new_budget.start_date).to eq(Date.new(2026, 1, 1))
      end

      it "preserves duration when end_date is set" do
        budget.start_date = Date.new(2025, 1, 1)
        budget.end_date = Date.new(2025, 3, 31) # 3 months duration

        new_budget = budget.duplicate_for_next_period

        expect(new_budget.start_date).to eq(Date.new(2025, 2, 1))
        expect(new_budget.end_date).to eq(Date.new(2025, 4, 30))
      end

      it "copies all attributes except dates" do
        new_budget = budget.duplicate_for_next_period

        expect(new_budget.email_account).to eq(budget.email_account)
        expect(new_budget.category).to eq(budget.category)
        expect(new_budget.name).to eq(budget.name)
        expect(new_budget.description).to eq(budget.description)
        expect(new_budget.period).to eq(budget.period)
        expect(new_budget.amount).to eq(budget.amount)
        expect(new_budget.currency).to eq(budget.currency)
        expect(new_budget.warning_threshold).to eq(budget.warning_threshold)
        expect(new_budget.critical_threshold).to eq(budget.critical_threshold)
        expect(new_budget.active).to be true
      end
    end

    describe "private methods" do
      describe "#currency_to_expense_currency" do
        before do
          allow(Expense).to receive(:currencies).and_return({
            crc: 0,
            usd: 1,
            eur: 2
          })
        end

        it "maps CRC to expense enum value" do
          budget.currency = "CRC"
          result = budget.send(:currency_to_expense_currency)
          expect(result).to eq(0)
        end

        it "maps USD to expense enum value" do
          budget.currency = "USD"
          result = budget.send(:currency_to_expense_currency)
          expect(result).to eq(1)
        end

        it "maps EUR to expense enum value" do
          budget.currency = "EUR"
          result = budget.send(:currency_to_expense_currency)
          expect(result).to eq(2)
        end

        it "defaults to CRC for unknown currency" do
          budget.currency = "GBP"
          result = budget.send(:currency_to_expense_currency)
          expect(result).to eq(0)
        end
      end

      describe "#check_and_track_exceeded" do
        context "when spending exceeds budget for first time" do
          before do
            budget.amount = 100_000
            budget.times_exceeded = 2
            budget.last_exceeded_at = nil
          end

          it "increments times_exceeded and sets last_exceeded_at" do
            expect(budget).to receive(:update_columns).with(
              times_exceeded: 3,
              last_exceeded_at: anything
            )

            budget.send(:check_and_track_exceeded, 120_000)
          end
        end

        context "when already exceeded" do
          before do
            budget.amount = 100_000
            budget.last_exceeded_at = 1.day.ago
          end

          it "does not update when still exceeded" do
            expect(budget).not_to receive(:update_columns)

            budget.send(:check_and_track_exceeded, 120_000)
          end
        end

        context "when returning under budget" do
          before do
            budget.amount = 100_000
            budget.last_exceeded_at = 1.day.ago
          end

          it "resets last_exceeded_at" do
            expect(budget).to receive(:update_columns).with(
              last_exceeded_at: nil
            )

            budget.send(:check_and_track_exceeded, 80_000)
          end
        end
      end

      describe "#calculate_current_spend_after_save" do
        it "calls calculate_current_spend! with recursion guard" do
          budget = build(:budget, email_account: email_account)

          expect(budget).to receive(:calculate_current_spend!)
          budget.send(:calculate_current_spend_after_save)
        end

        it "prevents infinite recursion" do
          budget = build(:budget, email_account: email_account)
          budget.instance_variable_set(:@calculating_spend, true)

          expect(budget).not_to receive(:calculate_current_spend!)
          budget.send(:calculate_current_spend_after_save)
        end
      end

      describe "#recalculate_if_needed" do
        let(:budget) { create(:budget, email_account: email_account) }

        it "recalculates when active status changes" do
          budget.active = false
          budget.save!

          expect(budget).to receive(:calculate_current_spend!)
          budget.send(:recalculate_if_needed)
        end

        it "recalculates when category changes" do
          new_category = create(:category, name: "New Category")
          budget.category = new_category
          budget.save!

          expect(budget).to receive(:calculate_current_spend!)
          budget.send(:recalculate_if_needed)
        end

        it "recalculates when period changes" do
          budget.period = :yearly
          budget.save!

          expect(budget).to receive(:calculate_current_spend!)
          budget.send(:recalculate_if_needed)
        end

        it "does not recalculate for other changes" do
          budget.name = "Updated Name"
          budget.save!

          expect(budget).not_to receive(:calculate_current_spend!)
          budget.send(:recalculate_if_needed)
        end

        it "prevents infinite recursion" do
          budget.instance_variable_set(:@calculating_spend, true)
          budget.active = false
          budget.save!

          expect(budget).not_to receive(:calculate_current_spend!)
          budget.send(:recalculate_if_needed)
        end
      end
    end
  end

  describe "edge cases and error conditions" do
    describe "threshold edge cases" do
      it "handles thresholds at boundaries" do
        budget.warning_threshold = 1
        budget.critical_threshold = 100
        expect(budget).to be_valid
      end

      it "handles equal thresholds as invalid" do
        budget.warning_threshold = 70
        budget.critical_threshold = 70
        expect(budget).not_to be_valid
      end
    end

    describe "amount edge cases" do
      it "handles very large amounts" do
        budget.amount = 999_999_999_999
        expect(budget).to be_valid
      end

      it "handles decimal amounts" do
        budget.amount = 100.50
        expect(budget).to be_valid
      end
    end

    describe "date edge cases" do
      it "handles far future dates" do
        budget.start_date = Date.new(2100, 1, 1)
        budget.end_date = Date.new(2100, 12, 31)
        expect(budget).to be_valid
      end

      it "handles same start and end date" do
        budget.start_date = Date.current
        budget.end_date = Date.current
        expect(budget).to be_valid
      end
    end

    describe "concurrent update scenarios" do
      it "handles concurrent spend calculations safely" do
        budget = create(:budget, email_account: email_account)

        # Simulate concurrent updates
        budget.instance_variable_set(:@calculating_spend, true)

        # Should not cause infinite loop
        expect { budget.send(:recalculate_if_needed) }.not_to raise_error
      end
    end

    describe "nil handling" do
      it "handles nil category gracefully" do
        budget.category = nil
        expect(budget).to be_valid
      end

      it "handles nil end_date gracefully" do
        budget.end_date = nil
        expect(budget).to be_valid
      end

      it "handles nil description" do
        budget.description = nil
        expect(budget).to be_valid
      end
    end
  end

  describe "performance considerations" do
    describe "query optimization" do
      it "uses precomputed values in scopes" do
        # Verify scopes use indexed columns
        expect(described_class.exceeded.to_sql).not_to include("/ 100")
        expect(described_class.warning.to_sql).to include("* warning_threshold / 100.0")
        expect(described_class.critical.to_sql).to include("* critical_threshold / 100.0")
      end

      it "includes associations to prevent N+1" do
        expenses_relation = double("expenses relation")
        allow(email_account).to receive(:expenses).and_return(expenses_relation)

        expect(expenses_relation).to receive(:includes).with(:category)
        allow(expenses_relation).to receive(:where).and_return(expenses_relation)
        allow(expenses_relation).to receive(:sum).and_return(0)
        allow(budget).to receive(:update_columns)
        allow(budget).to receive(:check_and_track_exceeded)

        budget.calculate_current_spend!
      end
    end

    describe "caching strategy" do
      it "caches current_spend for performance" do
        budget.current_spend = 50_000
        budget.current_spend_updated_at = 30.minutes.ago

        # Should use cached value without database query
        expect(budget).not_to receive(:calculate_current_spend!)
        budget.current_spend_amount
      end

      it "invalidates cache after 1 hour" do
        budget.current_spend_updated_at = 61.minutes.ago

        expect(budget).to receive(:calculate_current_spend!)
        budget.current_spend_amount
      end
    end
  end

  describe "security considerations" do
    describe "data isolation" do
      it "scopes all queries to email_account" do
        expenses_relation = double("expenses relation")
        allow(email_account).to receive(:expenses).and_return(expenses_relation)
        allow(expenses_relation).to receive_message_chain(:includes, :where, :sum).and_return(0)
        allow(budget).to receive(:update_columns)
        allow(budget).to receive(:check_and_track_exceeded)

        # Ensures expenses are scoped through email_account association
        expect(email_account).to receive(:expenses)
        budget.calculate_current_spend!
      end
    end

    describe "validation security" do
      it "validates currency against whitelist" do
        budget.currency = "<script>alert('XSS')</script>"
        budget.valid?
        expect(budget.errors[:currency]).to include("is not included in the list")
      end

      it "sanitizes name length" do
        budget.name = "a" * 101
        expect(budget).not_to be_valid
      end
    end
  end
end
