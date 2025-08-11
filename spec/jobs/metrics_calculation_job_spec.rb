# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetricsCalculationJob, type: :job do
  include ActiveJob::TestHelper

  let(:current_date) { Date.parse('2025-08-10') }
  let(:job) { described_class.new }
  let!(:email_account) { create(:email_account) }
  let!(:other_email_account) { create(:email_account, email: 'other@example.com') }

  describe '#perform' do
    context 'without email_account_id' do
      it 'raises error when email_account_id is not provided' do
        expect { job.perform(period: :month, reference_date: current_date) }
          .to raise_error(ArgumentError, /email_account_id is required/)
      end
    end
    
    context 'with specific period and date' do
      it 'calculates metrics for specified period and email_account' do
        calculator = instance_double(MetricsCalculator)
        expect(MetricsCalculator).to receive(:new)
          .with(email_account: email_account, period: :month, reference_date: current_date)
          .and_return(calculator)
        
        expect(calculator).to receive(:calculate).and_return({
          metrics: { total_amount: 100.0, transaction_count: 5 }
        })
        
        job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
      end
      
      it 'accepts email_account object directly' do
        calculator = instance_double(MetricsCalculator)
        expect(MetricsCalculator).to receive(:new)
          .with(email_account: email_account, period: :month, reference_date: current_date)
          .and_return(calculator)
        
        expect(calculator).to receive(:calculate).and_return({
          metrics: { total_amount: 100.0, transaction_count: 5 }
        })
        
        job.perform(email_account_id: email_account, period: :month, reference_date: current_date)
      end

      it 'logs calculation results with email_account_id' do
        create(:expense, email_account: email_account, amount: 100.0, transaction_date: current_date)
        
        expect(Rails.logger).to receive(:info)
          .with("Calculating metrics for account #{email_account.id}, period: month, date: #{current_date}")
        expect(Rails.logger).to receive(:info)
          .with(/Metrics calculated for account #{email_account.id}, month on #{current_date}/)
        expect(Rails.logger).to receive(:info)
          .with("MetricsCalculationJob completed successfully for account #{email_account.id}")
        
        job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
      end
    end

    context 'without specific period' do
      it 'calculates all periods for current date for specific email_account' do
        calculations_performed = []
        
        allow(MetricsCalculator).to receive(:new) do |args|
          calculator = instance_double(MetricsCalculator)
          allow(calculator).to receive(:calculate) do
            calculations_performed << args
            { metrics: { total_amount: 0.0, transaction_count: 0 } }
          end
          calculator
        end
        
        job.perform(email_account_id: email_account.id, reference_date: current_date)
        
        # Should calculate for all periods and multiple dates
        # day: 8 (past 7 days + today), week: 5 (past 4 weeks + current),
        # month: 4 (past 3 months + current), year: 2 (current + previous)
        # Total: 8 + 5 + 4 + 2 = 19
        expect(calculations_performed.size).to eq(19)
        
        # Check that all periods are covered
        periods_calculated = calculations_performed.map { |c| c[:period] }.uniq
        expect(periods_calculated).to include(:day, :week, :month, :year)
        
        # Check that all calculations are for the correct email_account
        expect(calculations_performed.all? { |c| c[:email_account] == email_account }).to be true
      end

      it 'pre-calculates multiple date ranges per period for specific email_account' do
        calculators = []
        
        allow(MetricsCalculator).to receive(:new) do |args|
          calculator = instance_double(MetricsCalculator)
          allow(calculator).to receive(:calculate).and_return({
            metrics: { total_amount: 0.0, transaction_count: 0 }
          })
          calculators << args
          calculator
        end
        
        job.perform(email_account_id: email_account.id, reference_date: current_date)
        
        # Check day calculations (past 7 days)
        day_calcs = calculators.select { |c| c[:period] == :day }
        expect(day_calcs.size).to eq(8)
        
        # Check week calculations (past 4 weeks)
        week_calcs = calculators.select { |c| c[:period] == :week }
        expect(week_calcs.size).to eq(5)
        
        # Check month calculations (past 3 months)
        month_calcs = calculators.select { |c| c[:period] == :month }
        expect(month_calcs.size).to eq(4)
        
        # Check year calculations (current and previous)
        year_calcs = calculators.select { |c| c[:period] == :year }
        expect(year_calcs.size).to eq(2)
      end
    end

    context 'with DashboardService integration' do
      it 'updates dashboard cache after calculation' do
        dashboard_service = instance_double(DashboardService)
        expect(DashboardService).to receive(:new).and_return(dashboard_service)
        expect(dashboard_service).to receive(:analytics)
        
        job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
      end
    end
    
    context 'data isolation' do
      it 'processes only specified email_account data' do
        # Create expenses for both accounts
        create(:expense, email_account: email_account, amount: 100.0, transaction_date: current_date)
        create(:expense, email_account: other_email_account, amount: 500.0, transaction_date: current_date)
        
        calculations = []
        allow(MetricsCalculator).to receive(:new) do |args|
          calculator = MetricsCalculator.allocate
          calculator.send(:initialize, **args)
          allow(calculator).to receive(:calculate).and_wrap_original do |m|
            result = m.call
            calculations << { account: args[:email_account].id, result: result }
            result
          end
          calculator
        end
        
        job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
        
        # Should only calculate for the specified account
        expect(calculations.all? { |c| c[:account] == email_account.id }).to be true
      end
    end

    context 'error handling' do
      it 'logs errors when calculation fails' do
        error = StandardError.new('Calculation failed')
        allow_any_instance_of(MetricsCalculator)
          .to receive(:calculate)
          .and_raise(error)
        
        expect(Rails.logger).to receive(:error)
          .with("MetricsCalculationJob failed: Calculation failed")
        expect(Rails.logger).to receive(:error)
          .with(anything) # backtrace
        
        expect { job.perform(email_account_id: email_account.id, period: :month) }.to raise_error(StandardError)
      end

      it 'logs error for failed individual calculations' do
        allow_any_instance_of(MetricsCalculator)
          .to receive(:calculate)
          .and_return({ error: 'DB connection lost', metrics: {} })
        
        expect(Rails.logger).to receive(:error)
          .with(/Metrics calculation failed for account \d+, month on #{current_date}: DB connection lost/)
        
        job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
      end
    end
  end

  describe 'job configuration' do
    it 'uses default queue' do
      expect(described_class.new.queue_name).to eq('default')
    end

    it 'is configured with retry on failure' do
      # Create a job that will fail
      allow_any_instance_of(MetricsCalculator)
        .to receive(:calculate)
        .and_raise(StandardError, 'Test error')
      
      perform_enqueued_jobs do
        expect {
          described_class.perform_later(email_account_id: email_account.id, period: :month)
        }.to raise_error(StandardError)
      end
    end
  end

  describe 'job enqueueing' do
    it 'can be enqueued' do
      expect {
        described_class.perform_later(email_account_id: email_account.id, period: :month)
      }.to have_enqueued_job(described_class)
        .with(email_account_id: email_account.id, period: :month)
        .on_queue('default')
    end

    it 'can be scheduled for later' do
      expect {
        described_class.set(wait: 1.hour).perform_later(email_account_id: email_account.id)
      }.to have_enqueued_job(described_class)
        .with(email_account_id: email_account.id)
        .at(be_within(1.second).of(1.hour.from_now))
    end
  end

  describe 'performance logging' do
    it 'formats amounts correctly in logs' do
      allow_any_instance_of(MetricsCalculator)
        .to receive(:calculate)
        .and_return({
          metrics: { 
            total_amount: 1234.56,
            transaction_count: 10
          }
        })
      
      # Expect multiple log messages
      expect(Rails.logger).to receive(:info)
        .with("Calculating metrics for account #{email_account.id}, period: month, date: #{current_date}")
      expect(Rails.logger).to receive(:info)
        .with(/10 transactions, total: \$1234\.56/)
      expect(Rails.logger).to receive(:info)
        .with("MetricsCalculationJob completed successfully for account #{email_account.id}")
      
      job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
    end
  end
end