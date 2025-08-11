# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetricsCalculator, '#calculate_trend_data' do
  let(:email_account) { create(:email_account) }
  let(:reference_date) { Date.current }
  let(:calculator) { described_class.new(email_account: email_account, reference_date: reference_date) }

  describe 'trend data calculation' do
    context 'with expenses over 7 days' do
      before do
        # Create expenses for each of the last 7 days
        (0..6).each do |days_ago|
          date = reference_date - days_ago.days
          create(:expense,
                 email_account: email_account,
                 transaction_date: date,
                 amount: 1000 * (days_ago + 1)) # Varying amounts
        end
      end

      it 'includes trend_data in calculate response' do
        result = calculator.calculate
        expect(result).to have_key(:trend_data)
      end

      it 'returns daily amounts for the last 7 days' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        expect(trend_data[:daily_amounts]).to be_an(Array)
        expect(trend_data[:daily_amounts].size).to eq(7)
      end

      it 'orders daily amounts from oldest to newest' do
        result = calculator.calculate
        trend_data = result[:trend_data]
        dates = trend_data[:daily_amounts].map { |d| d[:date] }

        expect(dates).to eq(dates.sort)
      end

      it 'calculates correct min and max values' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        expect(trend_data[:min]).to eq(1000.0)
        expect(trend_data[:max]).to eq(7000.0)
      end

      it 'calculates correct average' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        # Average of 1000, 2000, 3000, 4000, 5000, 6000, 7000 = 4000
        expect(trend_data[:average]).to eq(4000.0)
      end

      it 'calculates correct total' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        # Sum of 1000 + 2000 + 3000 + 4000 + 5000 + 6000 + 7000 = 28000
        expect(trend_data[:total]).to eq(28000.0)
      end

      it 'includes correct date range' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        expect(trend_data[:start_date]).to eq(reference_date - 6.days)
        expect(trend_data[:end_date]).to eq(reference_date)
      end
    end

    context 'with missing days' do
      before do
        # Only create expenses for some days
        create(:expense,
               email_account: email_account,
               transaction_date: reference_date,
               amount: 500)
        create(:expense,
               email_account: email_account,
               transaction_date: reference_date - 3.days,
               amount: 1500)
      end

      it 'fills missing days with zero amounts' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        expect(trend_data[:daily_amounts].size).to eq(7)

        # Check that missing days have zero amounts
        amounts = trend_data[:daily_amounts].map { |d| d[:amount] }
        expect(amounts.count(0.0)).to eq(5) # 5 days with no expenses
        expect(amounts).to include(500.0, 1500.0)
      end

      it 'calculates statistics correctly with zeros' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        expect(trend_data[:min]).to eq(0.0)
        expect(trend_data[:max]).to eq(1500.0)
        expect(trend_data[:average]).to be_within(0.01).of(2000.0 / 7) # Total 2000 / 7 days (with rounding)
        expect(trend_data[:total]).to eq(2000.0)
      end
    end

    context 'with multiple expenses on same day' do
      before do
        # Create multiple expenses on the same day
        3.times do
          create(:expense,
                 email_account: email_account,
                 transaction_date: reference_date,
                 amount: 100)
        end
      end

      it 'sums expenses for the same day' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        today_amount = trend_data[:daily_amounts].find { |d| d[:date] == reference_date }[:amount]
        expect(today_amount).to eq(300.0)
      end
    end

    context 'with no expenses' do
      it 'returns empty trend data with zeros' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        expect(trend_data[:daily_amounts].size).to eq(7)
        expect(trend_data[:daily_amounts].all? { |d| d[:amount] == 0.0 }).to be true
        expect(trend_data[:min]).to eq(0.0)
        expect(trend_data[:max]).to eq(0.0)
        expect(trend_data[:average]).to eq(0.0)
        expect(trend_data[:total]).to eq(0.0)
      end
    end

    context 'with different currencies' do
      before do
        # Create expenses with valid enum values
        expense1 = create(:expense,
                         email_account: email_account,
                         transaction_date: reference_date,
                         amount: 1000)
        expense1.crc! # Set to CRC currency

        expense2 = create(:expense,
                         email_account: email_account,
                         transaction_date: reference_date,
                         amount: 10)
        expense2.usd! # Set to USD currency
      end

      it 'includes all currencies in the sum' do
        result = calculator.calculate
        trend_data = result[:trend_data]

        today_amount = trend_data[:daily_amounts].find { |d| d[:date] == reference_date }[:amount]
        expect(today_amount).to eq(1010.0) # Treats all as same currency for simplicity
      end
    end

    context 'error handling' do
      it 'includes default trend data on error' do
        allow(calculator).to receive(:calculate_trend_data).and_raise(StandardError, 'Test error')

        result = calculator.calculate
        expect(result).to have_key(:trend_data)
        expect(result[:trend_data][:daily_amounts]).to eq([])
        expect(result[:trend_data][:min]).to eq(0.0)
        expect(result[:trend_data][:max]).to eq(0.0)
      end
    end

    context 'batch calculation' do
      before do
        create(:expense,
               email_account: email_account,
               transaction_date: reference_date,
               amount: 1000)
      end

      it 'includes trend data for all periods in batch calculation' do
        results = described_class.batch_calculate(
          email_account: email_account,
          periods: [ :day, :week, :month ],
          reference_date: reference_date
        )

        expect(results[:day]).to have_key(:trend_data)
        expect(results[:week]).to have_key(:trend_data)
        expect(results[:month]).to have_key(:trend_data)
      end

      it 'uses same 7-day window regardless of period' do
        results = described_class.batch_calculate(
          email_account: email_account,
          periods: [ :day, :week, :month, :year ],
          reference_date: reference_date
        )

        # All periods should have the same trend data (last 7 days)
        day_trend = results[:day][:trend_data]
        week_trend = results[:week][:trend_data]
        month_trend = results[:month][:trend_data]
        year_trend = results[:year][:trend_data]

        expect(day_trend[:start_date]).to eq(week_trend[:start_date])
        expect(day_trend[:start_date]).to eq(month_trend[:start_date])
        expect(day_trend[:start_date]).to eq(year_trend[:start_date])
        expect(day_trend[:total]).to eq(week_trend[:total])
        expect(day_trend[:total]).to eq(month_trend[:total])
        expect(day_trend[:total]).to eq(year_trend[:total])
      end
    end

    context 'performance' do
      before do
        # Create a reasonable number of expenses
        30.times do |i|
          create(:expense,
                 email_account: email_account,
                 transaction_date: reference_date - (i % 7).days,
                 amount: rand(100..5000))
        end
      end

      it 'calculates trend data within performance target' do
        start_time = Time.current
        calculator.calculate
        elapsed = Time.current - start_time

        expect(elapsed).to be < 0.1 # 100ms target
      end
    end
  end
end
