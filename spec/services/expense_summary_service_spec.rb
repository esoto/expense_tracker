require 'rails_helper'

RSpec.describe ExpenseSummaryService, integration: true do
  let(:category) { create(:category) }
  let(:email_account) { create(:email_account, :bac) }

  describe '#initialize', integration: true do
    it 'normalizes valid periods' do
      service = described_class.new("week")
      expect(service.period).to eq("week")
    end

    it 'defaults invalid periods to month' do
      service = described_class.new("invalid")
      expect(service.period).to eq("month")
    end

    it 'defaults nil period to month' do
      service = described_class.new(nil)
      expect(service.period).to eq("month")
    end
  end

  describe '#summary', integration: true do
    # Use a specific test timeframe to avoid conflicts with existing data
    let(:test_base_date) { Date.new(2023, 6, 15) } # Use a specific past date for test isolation
    let!(:week_expense) { create(:expense, amount: 100.0, transaction_date: test_base_date - 3.days, category: category, email_account: email_account) }
    let!(:month_expense) { create(:expense, amount: 200.0, transaction_date: test_base_date - 2.weeks, category: category, email_account: email_account) }
    let!(:year_expense) { create(:expense, amount: 300.0, transaction_date: test_base_date - 6.months, category: category, email_account: email_account) }
    
    # Mock Time.current to use our test timeframe
    around(:each) do |example|
      travel_to(test_base_date) do
        example.run
      end
    end

    context 'with week period' do
      let(:service) { described_class.new("week") }

      it 'returns weekly summary with correct structure' do
        result = service.summary

        expect(result).to include(
          :total_amount, :expense_count, :start_date, :end_date, :by_category
        )
        expect(result[:total_amount]).to eq(100.0)
        expect(result[:expense_count]).to eq(1)
        expect(result[:by_category][category.name]).to eq(100.0)
      end

      it 'includes proper date range for week' do
        result = service.summary

        expect(result[:start_date]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(result[:end_date]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end
    end

    context 'with month period' do
      let(:service) { described_class.new("month") }

      it 'returns monthly summary with correct totals' do
        result = service.summary

        expect(result).to include(
          :total_amount, :expense_count, :start_date, :end_date, :by_category
        )
        expect(result[:total_amount]).to eq(300.0) # week + month expenses
        expect(result[:expense_count]).to eq(2)
      end
    end

    context 'with year period' do
      let(:service) { described_class.new("year") }

      it 'returns yearly summary with monthly breakdown' do
        result = service.summary

        expect(result).to include(
          :total_amount, :expense_count, :start_date, :end_date,
          :by_category, :monthly_breakdown
        )
        expect(result[:total_amount]).to eq(600.0) # all expenses
        expect(result[:expense_count]).to eq(3)
        expect(result[:monthly_breakdown]).to be_a(Hash)
      end
    end

    context 'with invalid period that gets normalized' do
      let(:service) { described_class.new("something") }

      it 'falls back to monthly summary via else clause' do
        result = service.summary

        expect(result).to include(
          :total_amount, :expense_count, :start_date, :end_date, :by_category
        )
        # Should behave like monthly summary
        expect(result[:total_amount]).to eq(300.0) # week + month expenses
        expect(result[:expense_count]).to eq(2)
      end
    end
  end

  describe 'private methods', integration: true do
    let(:service) { described_class.new("month") }
    let(:private_test_date) { Date.new(2023, 3, 15) } # Different test date to avoid conflicts
    let(:start_date) { 1.month.ago.beginning_of_day }
    let(:end_date) { Time.current.end_of_day }

    around(:each) do |example|
      travel_to(private_test_date) do
        example.run
      end
    end

    before do
      create(:expense, amount: 150.0, transaction_date: private_test_date - 2.weeks, category: category, email_account: email_account)
    end

    describe '#total_amount_for_period', integration: true do
      it 'calculates total amount for given period' do
        total = service.send(:total_amount_for_period, start_date, end_date)
        expect(total).to eq(150.0)
      end
    end

    describe '#expense_count_for_period', integration: true do
      it 'counts expenses for given period' do
        count = service.send(:expense_count_for_period, start_date, end_date)
        expect(count).to eq(1)
      end
    end

    describe '#category_breakdown_for_period', integration: true do
      it 'groups expenses by category for given period' do
        breakdown = service.send(:category_breakdown_for_period, start_date, end_date)
        expect(breakdown[category.name]).to eq(150.0)
      end
    end
  end

  describe '.normalize_period', integration: true do
    let(:service) { described_class.new("month") }

    it 'accepts valid periods' do
      expect(service.send(:normalize_period, "week")).to eq("week")
      expect(service.send(:normalize_period, "month")).to eq("month")
      expect(service.send(:normalize_period, "year")).to eq("year")
    end

    it 'rejects invalid periods' do
      expect(service.send(:normalize_period, "day")).to eq("month")
      expect(service.send(:normalize_period, "invalid")).to eq("month")
      expect(service.send(:normalize_period, nil)).to eq("month")
    end
  end
end
