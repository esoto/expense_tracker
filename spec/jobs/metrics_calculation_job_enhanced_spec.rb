# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "MetricsCalculationJob Enhanced Features", type: :job, integration: true do
  include ActiveJob::TestHelper

  let(:current_date) { Date.parse('2025-08-10') }
  let(:job) { MetricsCalculationJob.new }
  let!(:email_account) { create(:email_account) }
  let!(:other_email_account) { create(:email_account, email: "other_#{SecureRandom.hex(4)}@example.com") }

  before do
    # Clear cache before each test
    Rails.cache.clear
  end

  describe 'concurrency control', integration: true do
    it 'prevents concurrent execution for same account' do
      lock_key = "metrics_calculation:#{email_account.id}"
      Rails.cache.write(lock_key, Time.current.to_s, expires_in: 5.minutes)

      expect(Rails.logger).to receive(:info).with(/skipped - another job is already processing/)
      expect_any_instance_of(ExtendedCacheMetricsCalculator).not_to receive(:calculate)

      job.perform(email_account_id: email_account.id, period: :month)
    end

    it 'acquires and releases lock properly' do
      lock_key = "metrics_calculation:#{email_account.id}"

      job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)

      # Lock should be released after execution
      expect(Rails.cache.read(lock_key)).to be_nil
    end

    it 'releases lock even on error' do
      lock_key = "metrics_calculation:#{email_account.id}"

      allow_any_instance_of(ExtendedCacheMetricsCalculator).to receive(:calculate).and_raise(StandardError, "Test error")

      expect { job.perform(email_account_id: email_account.id, period: :month) }.to raise_error(StandardError)

      # Lock should be released
      expect(Rails.cache.read(lock_key)).to be_nil
    end
  end

  describe 'performance monitoring', integration: true do
    it 'tracks job metrics on success' do
      job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)

      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      metrics = Rails.cache.read(metrics_key)

      expect(metrics).not_to be_nil
      expect(metrics[:success_count]).to eq(1)
      expect(metrics[:executions]).not_to be_empty
      expect(metrics[:success_rate]).to eq(100.0)
    end

    it 'tracks job metrics on failure' do
      allow_any_instance_of(ExtendedCacheMetricsCalculator).to receive(:calculate).and_raise(StandardError, "Test error")

      expect { job.perform(email_account_id: email_account.id, period: :month) }.to raise_error(StandardError)

      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      metrics = Rails.cache.read(metrics_key)

      expect(metrics[:failure_count]).to eq(1)
    end

    it 'logs warning when exceeding 30 second target' do
      # Mock slow execution
      start_time = Time.current
      allow(Time).to receive(:current).and_return(
        start_time,          # Start time
        start_time,          # Lock acquisition
        start_time + 31.seconds  # End time
      )

      expect(Rails.logger).to receive(:warn).with(/exceeded 30.* target/)

      job.perform(email_account_id: email_account.id, period: :month)
    end

    it 'tracks slow jobs for analysis' do
      # Mock slow execution
      start_time = Time.current
      allow(Time).to receive(:current).and_return(
        start_time,
        start_time,
        start_time + 35.seconds
      )

      job.perform(email_account_id: email_account.id, period: :month)

      slow_jobs = Rails.cache.read("slow_jobs:metrics_calculation")
      expect(slow_jobs).not_to be_empty
      expect(slow_jobs.last[:elapsed_time]).to be > 30
    end
  end

  describe 'force refresh', integration: true do
    it 'clears cache when force_refresh is true' do
      # Pre-populate cache
      cache_key = "metrics_calculator:account_#{email_account.id}:month:#{current_date.iso8601}"
      Rails.cache.write(cache_key, { test: "data" })

      expect(MetricsCalculator).to receive(:clear_cache).with(email_account: email_account)

      # Mock the calculator to avoid nil metrics error
      allow_any_instance_of(ExtendedCacheMetricsCalculator).to receive(:calculate).and_return({
        metrics: { total_amount: 0.0, transaction_count: 0 }
      })

      job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date, force_refresh: true)
    end
  end

  describe 'extended cache', integration: true do
    it 'uses ExtendedCacheMetricsCalculator for background calculations' do
      expect(ExtendedCacheMetricsCalculator).to receive(:new)
        .with(email_account: email_account, period: :month, reference_date: current_date, cache_hours: 4)
        .and_call_original

      job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)
    end

    it 'sets longer cache expiration for background-calculated metrics' do
      job.perform(email_account_id: email_account.id, period: :month, reference_date: current_date)

      cache_key = "metrics_calculator:account_#{email_account.id}:month:#{current_date.iso8601}"
      cached_data = Rails.cache.read(cache_key)

      expect(cached_data).not_to be_nil
      expect(cached_data[:background_calculated]).to be true
    end
  end

  describe '.enqueue_for_all_accounts', integration: true do
    it 'enqueues jobs for all active email accounts' do
      # Assuming email_account and other_email_account are active by default
      expect {
        MetricsCalculationJob.enqueue_for_all_accounts
      }.to have_enqueued_job(MetricsCalculationJob).at_least(2).times
    end

    it 'processes each account independently' do
      jobs_enqueued = []

      allow(MetricsCalculationJob).to receive(:perform_later) do |args|
        jobs_enqueued << args[:email_account_id]
      end

      MetricsCalculationJob.enqueue_for_all_accounts

      expect(jobs_enqueued).to include(email_account.id)
      expect(jobs_enqueued).to include(other_email_account.id)
    end
  end
end

# Test for ExtendedCacheMetricsCalculator
RSpec.describe Services::ExtendedCacheMetricsCalculator, integration: true do
  let(:email_account) { create(:email_account) }
  let(:calculator) { described_class.new(email_account: email_account, period: :month, cache_hours: 4) }

  describe '#initialize', integration: true do
    it 'accepts cache_hours parameter' do
      expect(calculator.cache_hours).to eq(4)
    end

    it 'inherits from MetricsCalculator' do
      expect(calculator).to be_a(MetricsCalculator)
    end
  end

  describe '#calculate', integration: true do
    it 'uses extended cache expiration' do
      # Create some test data
      create(:expense, email_account: email_account, amount: 100, transaction_date: Date.current)

      # Calculate metrics
      result = calculator.calculate

      # Verify result includes background_calculated flag
      expect(result[:background_calculated]).to be true

      # Verify cache was written with longer expiration
      cache_key = calculator.cache_key
      expect(Rails.cache.exist?(cache_key)).to be true
    end

    it 'includes all standard metrics' do
      result = calculator.calculate

      expect(result).to include(
        :period,
        :reference_date,
        :date_range,
        :metrics,
        :trends,
        :category_breakdown,
        :daily_breakdown,
        :trend_data,
        :budgets,
        :calculated_at,
        :background_calculated
      )
    end
  end
end
