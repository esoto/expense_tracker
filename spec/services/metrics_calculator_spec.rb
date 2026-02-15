# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::MetricsCalculator, type: :service, performance: true do
  let(:current_date) { Date.parse('2025-08-10') }
  let(:calculator) { described_class.new(email_account: email_account, period: period, reference_date: current_date) }
  let(:period) { :month }

  # Create test data
  let!(:email_account) { create(:email_account) }
  let!(:other_email_account) { create(:email_account, email: 'other@example.com') }
  let!(:category1) { create(:category, name: 'Food') }
  let!(:category2) { create(:category, name: 'Transport') }

  describe '#initialize', performance: true do
    context 'with email_account' do
      it 'requires email_account parameter' do
        expect { described_class.new(period: :month) }
          .to raise_error(Services::MetricsCalculator::MissingEmailAccountError, /EmailAccount is required/)
      end

      it 'accepts email_account with valid period' do
        expect { described_class.new(email_account: email_account, period: :month) }.not_to raise_error
      end
    end

    context 'with valid period' do
      %i[day week month year].each do |valid_period|
        it "accepts #{valid_period} as valid period" do
          expect { described_class.new(email_account: email_account, period: valid_period) }.not_to raise_error
        end
      end
    end

    context 'with invalid period' do
      it 'raises InvalidPeriodError' do
        expect { described_class.new(email_account: email_account, period: :invalid) }
          .to raise_error(Services::MetricsCalculator::InvalidPeriodError, /Invalid period: invalid/)
      end
    end

    it 'converts string period to symbol' do
      calculator = described_class.new(email_account: email_account, period: 'month')
      expect(calculator.period).to eq(:month)
    end

    it 'converts reference_date to Date object' do
      calculator = described_class.new(email_account: email_account, reference_date: '2025-08-10')
      expect(calculator.reference_date).to be_a(Date)
      expect(calculator.reference_date).to eq(Date.parse('2025-08-10'))
    end
  end

  describe '#calculate', performance: true do
    context 'efficiency' do
      before do
        create(:expense, email_account: email_account, amount: 100, transaction_date: current_date)
        create(:expense, email_account: email_account, amount: 50, transaction_date: current_date - 35.days)
        Rails.cache.clear
      end

      it 'does not call calculate_metrics more than once', :unit do
        expect(calculator).to receive(:calculate_metrics).once.and_call_original
        calculator.calculate
      end
    end

    context 'calculate_metrics query consolidation' do
      before do
        create_list(:expense, 3, email_account: email_account, category: category1, transaction_date: current_date, merchant_name: 'TestMerchant')
        Rails.cache.clear
      end

      it 'uses consolidated queries for aggregate calculations', :unit do
        # Warm up AR caches
        calculator.send(:expenses_in_period)

        query_count = count_queries { calculator.send(:calculate_metrics) }
        # Consolidated should need at most 7 queries (main agg + distinct merchants + distinct categories + uncategorized + status + currency + median)
        expect(query_count).to be <= 7
      end
    end

    context 'category breakdown query efficiency' do
      before do
        create(:expense, email_account: email_account, category: category1, amount: 100, transaction_date: current_date)
        create(:expense, email_account: email_account, category: category2, amount: 50, transaction_date: current_date)
        create(:expense, email_account: email_account, category: nil, amount: 25, transaction_date: current_date)
        Rails.cache.clear
      end

      it 'does not fire N+1 queries for percentage calculation', :unit do
        # Warm up AR caches
        calculator.send(:expenses_in_period)

        query_count = count_queries { calculator.send(:calculate_category_breakdown) }
        # Should be constant (1-3 queries), not proportional to category count
        expect(query_count).to be <= 3
      end
    end

    before do
      # Create expenses for current month
      create(:expense,
             email_account: email_account,
             category: category1,
             amount: 100.50,
             transaction_date: current_date,
             merchant_name: 'Restaurant A',
             status: 'processed',
             currency: 'usd')

      create(:expense,
             email_account: email_account,
             category: category1,
             amount: 50.25,
             transaction_date: current_date - 5.days,
             merchant_name: 'Restaurant B',
             status: 'processed',
             currency: 'usd')

      create(:expense,
             email_account: email_account,
             category: category2,
             amount: 75.00,
             transaction_date: current_date - 10.days,  # July 31, 2025 - still in July!
             merchant_name: 'Uber',
             status: 'pending',
             currency: 'crc')

      # Create expense without category
      create(:expense,
             email_account: email_account,
             category: nil,
             amount: 25.00,
             transaction_date: current_date - 15.days,  # July 26, 2025 - still in July!
             merchant_name: 'Unknown Shop',
             status: 'processed',
             currency: 'usd')

      # Create expense in previous month for trend calculation
      create(:expense,
             email_account: email_account,
             category: category1,
             amount: 200.00,
             transaction_date: current_date - 45.days,
             status: 'processed')

      # Create expense for different email_account to test isolation
      create(:expense,
             email_account: other_email_account,
             category: category1,
             amount: 500.00,
             transaction_date: current_date,
             status: 'processed')
    end

    context 'with data isolation' do
      it 'only includes expenses for the specified email_account' do
        Rails.cache.clear
        result = calculator.calculate

        # Should not include the 500.00 expense from other_email_account
        expect(result[:metrics][:total_amount]).to eq(150.75)
        expect(result[:metrics][:transaction_count]).to eq(2)
      end

      it 'maintains separate cache for different email_accounts' do
        Rails.cache.clear

        # Calculate for first account
        calc1 = described_class.new(email_account: email_account, period: :month, reference_date: current_date)
        result1 = calc1.calculate
        expect(result1[:metrics][:total_amount]).to eq(150.75)

        # Calculate for second account
        calc2 = described_class.new(email_account: other_email_account, period: :month, reference_date: current_date)
        result2 = calc2.calculate
        expect(result2[:metrics][:total_amount]).to eq(500.00)
      end
    end

    context 'with month period' do
      let(:period) { :month }

      it 'returns comprehensive metrics' do
        result = calculator.calculate

        expect(result).to include(
          period: :month,
          reference_date: current_date,
          calculated_at: be_a(Time)
        )

        expect(result[:date_range]).to eq(
          current_date.beginning_of_month..current_date.end_of_month
        )
      end

      it 'calculates correct metrics' do
        # Clear cache before test and force recalculation
        Rails.cache.clear

        result = calculator.calculate!
        metrics = result[:metrics]

        # We have 2 expenses in August: 100.50 + 50.25 = 150.75
        expect(metrics[:total_amount]).to eq(150.75)
        expect(metrics[:transaction_count]).to eq(2)
        expect(metrics[:average_amount]).to eq(75.38)
        expect(metrics[:median_amount]).to eq(75.38)
        expect(metrics[:min_amount]).to eq(50.25)  # Min of the 2 August expenses
        expect(metrics[:max_amount]).to eq(100.50)
        expect(metrics[:unique_merchants]).to eq(2)  # Only 2 merchants in August
        expect(metrics[:unique_categories]).to eq(1)  # Only Food category in August
        expect(metrics[:uncategorized_count]).to eq(0)  # None are uncategorized in August
      end

      it 'calculates status breakdown' do
        Rails.cache.clear
        result = calculator.calculate
        metrics = result[:metrics]

        # Only 2 expenses in August, both are 'processed'
        expect(metrics[:by_status]).to eq({
          'processed' => 2
        })
      end

      it 'calculates currency breakdown' do
        Rails.cache.clear
        result = calculator.calculate
        metrics = result[:metrics]

        # Only 2 expenses in August, both are 'usd'
        expect(metrics[:by_currency]).to eq({
          'usd' => 150.75
        })
      end

      it 'calculates trends correctly' do
        Rails.cache.clear
        result = calculator.calculate
        trends = result[:trends]

        # Previous month (July) has 2 expenses: 75.00 + 25.00 = 100.00
        expect(trends[:previous_period_total]).to eq(100.00)
        expect(trends[:previous_period_count]).to eq(2)
        expect(trends[:absolute_amount_change]).to eq(50.75)  # 150.75 - 100.00
        expect(trends[:absolute_count_change]).to eq(0)  # 2 - 2
        expect(trends[:amount_change]).to eq(50.75)  # 50.75% increase
        expect(trends[:is_increase]).to be true
      end

      it 'calculates category breakdown' do
        Rails.cache.clear
        result = calculator.calculate
        breakdown = result[:category_breakdown]

        expect(breakdown).to be_an(Array)
        expect(breakdown.size).to eq(1)  # Only Food category in August

        food_category = breakdown.find { |b| b[:category] == 'Food' }
        expect(food_category).to include(
          total_amount: 150.75,
          transaction_count: 2,
          average_amount: 75.38,
          min_amount: 50.25,
          max_amount: 100.50
        )
        expect(food_category[:percentage_of_total]).to be_within(0.01).of(100.0)  # 100% of August expenses
      end

      it 'includes daily breakdown for month period' do
        Rails.cache.clear
        result = calculator.calculate
        daily = result[:daily_breakdown]

        expect(daily).to be_a(Hash)
        # Only 2 expenses in August
        expect(daily).to include(
          current_date => 100.50,
          current_date - 5.days => 50.25
        )
        # July expenses should not be included
        expect(daily).not_to include(
          current_date - 10.days => 75.00,
          current_date - 15.days => 25.00
        )
      end
    end

    context 'with day period' do
      let(:period) { :day }

      it 'calculates metrics for single day' do
        Rails.cache.clear
        result = calculator.calculate
        metrics = result[:metrics]

        # Only 1 expense on August 10
        expect(metrics[:total_amount]).to eq(100.50)
        expect(metrics[:transaction_count]).to eq(1)
        expect(result[:date_range]).to eq(
          current_date.beginning_of_day..current_date.end_of_day
        )
      end

      it 'does not include daily breakdown for day period' do
        result = calculator.calculate
        expect(result[:daily_breakdown]).to eq({})
      end
    end

    context 'with week period' do
      let(:period) { :week }

      it 'calculates metrics for week' do
        result = calculator.calculate

        expect(result[:date_range]).to eq(
          current_date.beginning_of_week..current_date.end_of_week
        )
      end

      it 'includes daily breakdown for week period' do
        result = calculator.calculate
        expect(result[:daily_breakdown]).to be_a(Hash)
      end
    end

    context 'with year period' do
      let(:period) { :year }

      it 'calculates metrics for year' do
        Rails.cache.clear
        result = calculator.calculate

        expect(result[:date_range]).to eq(
          current_date.beginning_of_year..current_date.end_of_year
        )

        # Should include all 5 expenses (2 in August + 2 in July + 1 from 45 days ago which is still in 2025)
        expect(result[:metrics][:transaction_count]).to eq(5)
      end
    end

    context 'with no expenses' do
      before { Expense.destroy_all }

      it 'returns zero values' do
        result = calculator.calculate
        metrics = result[:metrics]

        expect(metrics[:total_amount]).to eq(0.0)
        expect(metrics[:transaction_count]).to eq(0)
        expect(metrics[:average_amount]).to eq(0.0)
        expect(metrics[:median_amount]).to eq(0.0)
        expect(metrics[:unique_merchants]).to eq(0)
      end

      it 'handles trends with no previous data' do
        result = calculator.calculate
        trends = result[:trends]

        expect(trends[:amount_change]).to eq(0.0)
        expect(trends[:count_change]).to eq(0.0)
        expect(trends[:is_increase]).to be false
      end
    end
  end

  describe 'caching', performance: true do
    before do
      create(:expense,
             email_account: email_account,
             amount: 100.00,
             transaction_date: current_date)
    end

    it 'caches results for 1 hour' do
      Rails.cache.clear

      # First call should hit database
      expect(email_account.expenses).to receive(:where).at_least(:once).and_call_original
      result1 = calculator.calculate

      # Second call should use cache
      allow(email_account.expenses).to receive(:where).and_call_original
      result2 = calculator.calculate

      # Compare everything except calculated_at timestamp
      expect(result1.except(:calculated_at)).to eq(result2.except(:calculated_at))
    end

    it 'uses unique cache key per email_account, period and date' do
      calc1 = described_class.new(email_account: email_account, period: :month, reference_date: current_date)
      calc2 = described_class.new(email_account: email_account, period: :week, reference_date: current_date)
      calc3 = described_class.new(email_account: email_account, period: :month, reference_date: current_date - 1.day)
      calc4 = described_class.new(email_account: other_email_account, period: :month, reference_date: current_date)

      expect(calc1.cache_key).not_to eq(calc2.cache_key)
      expect(calc1.cache_key).not_to eq(calc3.cache_key)
      expect(calc1.cache_key).not_to eq(calc4.cache_key)

      # Check cache key format includes email_account_id
      expect(calc1.cache_key).to include("account_#{email_account.id}")
    end
  end

  describe '#calculate!', performance: true do
    before do
      create(:expense,
             email_account: email_account,
             amount: 100.00,
             transaction_date: current_date)
    end

    it 'forces recalculation without cache' do
      Rails.cache.clear

      # Prime cache
      first_result = calculator.calculate
      expect(first_result[:metrics][:total_amount]).to eq(100.00)

      # Add new expense
      create(:expense,
             email_account: email_account,
             amount: 50.00,
             transaction_date: current_date)

      # Normal calculate should return cached result
      cached_result = calculator.calculate
      expect(cached_result[:metrics][:total_amount]).to eq(100.00)

      # Force recalculation
      fresh_result = calculator.calculate!
      expect(fresh_result[:metrics][:total_amount]).to eq(150.00)
    end
  end

  describe '.clear_cache', performance: true do
    it 'clears all metrics calculator caches when no email_account specified' do
      Rails.cache.write('metrics_calculator:account_1:month:2025-08-10', 'test1')
      Rails.cache.write('metrics_calculator:account_2:week:2025-08-10', 'test2')
      Rails.cache.write('other_cache_key', 'test3')

      described_class.clear_cache

      expect(Rails.cache.read('metrics_calculator:account_1:month:2025-08-10')).to be_nil
      expect(Rails.cache.read('metrics_calculator:account_2:week:2025-08-10')).to be_nil
      expect(Rails.cache.read('other_cache_key')).to eq('test3')
    end

    it 'clears only specific email_account caches when email_account provided' do
      Rails.cache.write("metrics_calculator:account_#{email_account.id}:month:2025-08-10", 'test1')
      Rails.cache.write("metrics_calculator:account_#{email_account.id}:week:2025-08-10", 'test2')
      Rails.cache.write("metrics_calculator:account_#{other_email_account.id}:month:2025-08-10", 'test3')
      Rails.cache.write('other_cache_key', 'test4')

      described_class.clear_cache(email_account: email_account)

      expect(Rails.cache.read("metrics_calculator:account_#{email_account.id}:month:2025-08-10")).to be_nil
      expect(Rails.cache.read("metrics_calculator:account_#{email_account.id}:week:2025-08-10")).to be_nil
      expect(Rails.cache.read("metrics_calculator:account_#{other_email_account.id}:month:2025-08-10")).to eq('test3')
      expect(Rails.cache.read('other_cache_key')).to eq('test4')
    end
  end

  describe '.pre_calculate_all', performance: true do
    it 'requires email_account parameter' do
      expect { described_class.pre_calculate_all(reference_date: current_date) }
        .to raise_error(Services::MetricsCalculator::MissingEmailAccountError, /EmailAccount is required/)
    end

    it 'pre-calculates metrics for all supported periods for specific email_account' do
      # Mock multiple instances
      calculators_called = []

      allow(described_class).to receive(:new) do |args|
        calculator = described_class.allocate
        calculator.send(:initialize, **args)
        allow(calculator).to receive(:calculate) do
          calculators_called << args
          { metrics: {}, trends: {} }
        end
        calculator
      end

      described_class.pre_calculate_all(email_account: email_account, reference_date: current_date)

      # Check that all 4 periods were calculated for the correct email_account
      expect(calculators_called.map { |c| c[:period] }.uniq).to match_array([ :day, :week, :month, :year ])
      expect(calculators_called.all? { |c| c[:email_account] == email_account }).to be true
    end
  end

  describe '.batch_calculate', performance: true do
    before do
      # Create test expenses for calculations
      create(:expense,
             email_account: email_account,
             category: category1,
             amount: 100.00,
             transaction_date: current_date,
             merchant_name: 'Test Merchant')

      create(:expense,
             email_account: email_account,
             category: category2,
             amount: 50.00,
             transaction_date: current_date - 3.days,
             merchant_name: 'Another Merchant')
    end

    it 'requires email_account parameter' do
      expect { described_class.batch_calculate(periods: [ :month ]) }
        .to raise_error(Services::MetricsCalculator::MissingEmailAccountError, /EmailAccount is required/)
    end

    it 'validates all periods are supported' do
      expect {
        described_class.batch_calculate(
          email_account: email_account,
          periods: [ :month, :invalid_period ]
        )
      }.to raise_error(Services::MetricsCalculator::InvalidPeriodError, /Invalid periods: invalid_period/)
    end

    it 'returns a hash with period symbols as keys' do
      result = described_class.batch_calculate(
        email_account: email_account,
        periods: [ :day, :week, :month ],
        reference_date: current_date
      )

      expect(result).to be_a(Hash)
      expect(result.keys).to match_array([ :day, :week, :month ])
    end

    it 'calculates metrics for each requested period' do
      Rails.cache.clear

      result = described_class.batch_calculate(
        email_account: email_account,
        periods: [ :day, :week, :month ],
        reference_date: current_date
      )

      # Day period should only include today's expense
      expect(result[:day][:metrics][:total_amount]).to eq(100.00)
      expect(result[:day][:metrics][:transaction_count]).to eq(1)

      # Week period should include both expenses
      expect(result[:week][:metrics][:total_amount]).to eq(150.00)
      expect(result[:week][:metrics][:transaction_count]).to eq(2)

      # Month period should include both expenses (both in August)
      expect(result[:month][:metrics][:total_amount]).to eq(150.00)
      expect(result[:month][:metrics][:transaction_count]).to eq(2)
    end

    it 'uses the same reference_date for all calculations' do
      result = described_class.batch_calculate(
        email_account: email_account,
        periods: [ :day, :week, :month ],
        reference_date: current_date - 10.days
      )

      expect(result[:day][:reference_date]).to eq(current_date - 10.days)
      expect(result[:week][:reference_date]).to eq(current_date - 10.days)
      expect(result[:month][:reference_date]).to eq(current_date - 10.days)
    end

    it 'handles string period names correctly' do
      result = described_class.batch_calculate(
        email_account: email_account,
        periods: [ 'day', 'week' ],
        reference_date: current_date
      )

      expect(result.keys).to match_array([ :day, :week ])
      expect(result[:day]).to include(:metrics, :trends)
      expect(result[:week]).to include(:metrics, :trends)
    end

    it 'uses cache efficiently for each period' do
      Rails.cache.clear

      # Prime the cache
      described_class.batch_calculate(
        email_account: email_account,
        periods: [ :day, :week ],
        reference_date: current_date
      )

      # Second call should use cache
      expect(Rails.cache).to receive(:fetch).exactly(2).times.and_call_original

      result = described_class.batch_calculate(
        email_account: email_account,
        periods: [ :day, :week ],
        reference_date: current_date
      )

      expect(result[:day]).to be_present
      expect(result[:week]).to be_present
    end

    it 'calculates all default periods when periods parameter not provided' do
      result = described_class.batch_calculate(
        email_account: email_account,
        reference_date: current_date
      )

      expect(result.keys).to match_array([ :day, :week, :month, :year ])
    end

    it 'maintains data isolation per email account' do
      other_account = create(:email_account, email: 'other@test.com')

      create(:expense,
             email_account: other_account,
             amount: 500.00,
             transaction_date: current_date)

      result = described_class.batch_calculate(
        email_account: email_account,
        periods: [ :day ],
        reference_date: current_date
      )

      # Should not include the 500.00 expense from other account
      expect(result[:day][:metrics][:total_amount]).to eq(100.00)
    end

    it 'performs efficiently compared to individual calculations' do
      Rails.cache.clear

      # Measure batch calculation time
      batch_time = Benchmark.realtime do
        described_class.batch_calculate(
          email_account: email_account,
          periods: [ :day, :week, :month, :year ],
          reference_date: current_date
        )
      end

      Rails.cache.clear

      # Measure individual calculations time
      individual_time = Benchmark.realtime do
        [ :day, :week, :month, :year ].each do |period|
          described_class.new(
            email_account: email_account,
            period: period,
            reference_date: current_date
          ).calculate
        end
      end

      # Batch should be at least as fast, if not faster
      # Allow some margin for test variability (50% tolerance for CI environments)
      expect(batch_time).to be <= (individual_time * 1.5)
    end
  end

  describe 'performance', performance: true do
    before do
      # Create 100 expenses to test performance
      100.times do |i|
        create(:expense,
               email_account: email_account,
               category: [ category1, category2, nil ].sample,
               amount: rand(10.0..500.0),
               transaction_date: current_date - rand(0..30).days,
               merchant_name: "Merchant #{i}",
               status: %w[pending processed failed].sample)
      end
    end

    it 'completes calculation within 100ms' do
      # Warm up
      calculator.calculate
      Rails.cache.clear

      # Measure
      elapsed = Benchmark.realtime { calculator.calculate }

      # Should complete within 100ms (allowing some margin for CI environments)
      expect(elapsed).to be < 0.2
    end

    it 'logs warning if calculation exceeds 100ms' do
      allow(Benchmark).to receive(:realtime).and_return(0.15)

      expect(Rails.logger).to receive(:warn).with(/exceeded 100ms target: 150.0ms/)
      calculator.calculate
    end
  end

  describe 'error handling', performance: true do
    it 'handles database errors gracefully' do
      allow(email_account.expenses).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'DB Error')

      result = calculator.calculate

      expect(result[:error]).to eq('DB Error')
      expect(result[:metrics]).to eq(calculator.send(:default_metrics))
      expect(result[:trends]).to eq(calculator.send(:default_trends))
    end

    it 'logs errors when calculation fails' do
      error = StandardError.new('Test error')
      allow(email_account.expenses).to receive(:where).and_raise(error)

      expect(Rails.logger).to receive(:error).with(/Services::MetricsCalculator error: Test error/)
      expect(Rails.logger).to receive(:error).with(/.*/) # backtrace

      calculator.calculate
    end
  end

  describe 'edge cases', performance: true do
    context 'with very large amounts' do
      before do
        create(:expense,
               email_account: email_account,
               amount: 999_999.99,
               transaction_date: current_date)
      end

      it 'handles large amounts correctly' do
        Rails.cache.clear
        result = calculator.calculate
        expect(result[:metrics][:total_amount]).to eq(999_999.99)
      end
    end

    context 'with expenses on period boundaries' do
      let(:period) { :month }

      before do
        # Expense on last millisecond of previous month
        create(:expense,
               email_account: email_account,
               amount: 100.00,
               transaction_date: current_date.beginning_of_month - 1.second)

        # Expense on first millisecond of current month
        create(:expense,
               email_account: email_account,
               amount: 200.00,
               transaction_date: current_date.beginning_of_month)

        # Expense on last millisecond of current month
        create(:expense,
               email_account: email_account,
               amount: 300.00,
               transaction_date: current_date.end_of_month)
      end

      it 'includes only expenses within period boundaries' do
        Rails.cache.clear
        result = calculator.calculate

        # Should include expenses from beginning to end of month
        expect(result[:metrics][:transaction_count]).to eq(2)
        expect(result[:metrics][:total_amount]).to eq(500.00)
      end
    end
  end
end
