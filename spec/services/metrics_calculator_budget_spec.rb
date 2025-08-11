# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetricsCalculator, 'budget calculations' do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:calculator) { described_class.new(email_account: email_account, period: :month) }

  describe '#calculate_budget_data' do
    context 'without any budgets' do
      it 'returns default budget data' do
        result = calculator.calculate
        budget_data = result[:budgets]

        expect(budget_data[:has_budget]).to be false
        expect(budget_data[:general_budget]).to be nil
        expect(budget_data[:category_budgets]).to be_empty
        expect(budget_data[:total_budget_amount]).to eq(0.0)
        expect(budget_data[:overall_usage]).to eq(0.0)
      end
    end

    context 'with a general budget' do
      let!(:budget) { create(:budget, email_account: email_account, period: 'monthly', amount: 1000000) }

      before do
        # Create some expenses for the current month
        create(:expense, email_account: email_account, amount: 250000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, amount: 150000, transaction_date: Date.current, currency: 'crc')
      end

      it 'includes budget information in metrics' do
        result = calculator.calculate
        budget_data = result[:budgets]

        expect(budget_data[:has_budget]).to be true
        expect(budget_data[:general_budget]).to be_present
        expect(budget_data[:general_budget][:id]).to eq(budget.id)
        expect(budget_data[:general_budget][:amount]).to eq(1000000.0)
        expect(budget_data[:general_budget][:current_spend]).to eq(400000.0)
        expect(budget_data[:general_budget][:usage_percentage]).to eq(40.0)
        expect(budget_data[:general_budget][:status]).to eq(:good)
      end

      it 'calculates overall usage correctly' do
        result = calculator.calculate
        expect(result[:budgets][:overall_usage]).to eq(40.0)
      end
    end

    context 'with category-specific budgets' do
      let!(:food_budget) { create(:budget, email_account: email_account, category: category, period: 'monthly', amount: 300000) }
      let!(:transport_category) { create(:category, name: 'Transporte') }
      let!(:transport_budget) { create(:budget, email_account: email_account, category: transport_category, period: 'monthly', amount: 200000) }

      before do
        create(:expense, email_account: email_account, category: category, amount: 150000, transaction_date: Date.current, currency: 'crc')
        create(:expense, email_account: email_account, category: transport_category, amount: 100000, transaction_date: Date.current, currency: 'crc')
      end

      it 'includes all category budgets' do
        result = calculator.calculate
        budget_data = result[:budgets]

        expect(budget_data[:has_budget]).to be true
        expect(budget_data[:category_budgets].size).to eq(2)

        food_budget_data = budget_data[:category_budgets].find { |b| b[:category] == category.name }
        expect(food_budget_data[:current_spend]).to eq(150000.0)
        expect(food_budget_data[:usage_percentage]).to eq(50.0)

        transport_budget_data = budget_data[:category_budgets].find { |b| b[:category] == transport_category.name }
        expect(transport_budget_data[:current_spend]).to eq(100000.0)
        expect(transport_budget_data[:usage_percentage]).to eq(50.0)
      end

      it 'calculates total budget amount' do
        result = calculator.calculate
        expect(result[:budgets][:total_budget_amount]).to eq(500000.0)
      end

      it 'calculates weighted average usage' do
        result = calculator.calculate
        # (150000 + 100000) / 500000 * 100 = 50%
        expect(result[:budgets][:overall_usage]).to eq(50.0)
      end
    end

    context 'with budget status variations' do
      let!(:good_budget) { create(:budget, :at_warning, email_account: email_account, period: 'monthly', warning_threshold: 80) }

      it 'returns correct status for warning level' do
        result = calculator.calculate
        budget_data = result[:budgets][:general_budget]

        expect(budget_data[:status]).to eq(:good) # 75% is below 80% warning
        expect(budget_data[:status_color]).to eq('emerald-600')
      end

      context 'with exceeded budget' do
        let!(:exceeded_budget) { create(:budget, :exceeded, email_account: email_account, period: 'monthly') }

        it 'returns exceeded status' do
          result = calculator.calculate
          budget_data = result[:budgets][:general_budget]

          expect(budget_data[:status]).to eq(:exceeded)
          expect(budget_data[:status_color]).to eq('rose-600')
          expect(budget_data[:on_track]).to be false
        end
      end
    end

    context 'with different periods' do
      let(:weekly_calculator) { described_class.new(email_account: email_account, period: :week) }
      let!(:weekly_budget) { create(:budget, :weekly, email_account: email_account) }

      it 'matches budget period with calculator period' do
        result = weekly_calculator.calculate
        budget_data = result[:budgets]

        expect(budget_data[:has_budget]).to be true
        expect(budget_data[:general_budget][:period]).to eq('weekly')
      end
    end

    context 'with historical adherence' do
      let!(:budget) { create(:budget, email_account: email_account, period: 'monthly') }

      it 'includes historical adherence data' do
        result = calculator.calculate
        adherence = result[:budgets][:historical_adherence]

        expect(adherence).to be_present
        expect(adherence[:periods_analyzed]).to eq(6)
        expect(adherence[:trend]).to be_present
        expect(adherence[:message]).to be_present
      end
    end

    context 'error handling' do
      it 'returns default budget data on error' do
        allow_any_instance_of(Budget).to receive(:calculate_current_spend!).and_raise(StandardError, 'Test error')

        result = calculator.calculate
        budget_data = result[:budgets]

        expect(budget_data[:has_budget]).to be false
        expect(budget_data[:general_budget]).to be nil
      end
    end
  end

  describe 'performance' do
    before do
      # Create multiple budgets and expenses
      3.times do |i|
        category = create(:category, name: "Category #{i}")
        create(:budget, email_account: email_account, category: category, period: 'monthly')

        5.times do
          create(:expense,
            email_account: email_account,
            category: category,
            amount: rand(10000..50000),
            transaction_date: Date.current - rand(0..30).days,
            currency: 'crc'
          )
        end
      end
    end

    it 'calculates budget data within performance target' do
      time = Benchmark.realtime do
        calculator.calculate
      end

      expect(time).to be < 0.5 # Allow 500ms for budget calculations
    end
  end
end
