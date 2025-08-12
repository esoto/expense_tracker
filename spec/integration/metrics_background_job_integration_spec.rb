# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Metrics Background Job Integration", type: :integration do
  let(:email_account) { create(:email_account) }

  before do
    Rails.cache.clear
  end

  describe "Complete metric calculation flow" do
    it "pre-calculates metrics through background job" do
      # Create test expenses
      create_list(:expense, 5, email_account: email_account, amount: 100, transaction_date: Date.current)
      create_list(:expense, 3, email_account: email_account, amount: 50, transaction_date: 1.day.ago)

      # Run the background job
      job = MetricsCalculationJob.new
      job.perform(email_account_id: email_account.id, period: :month)

      # Verify metrics were calculated and cached
      cache_key = "metrics_calculator:account_#{email_account.id}:month:#{Date.current.iso8601}"
      cached_data = Rails.cache.read(cache_key)

      expect(cached_data).not_to be_nil
      expect(cached_data[:background_calculated]).to be true
      expect(cached_data[:metrics][:total_amount]).to eq(650.0)
      expect(cached_data[:metrics][:transaction_count]).to eq(8)
    end

    it "refreshes metrics when expense is created" do
      # Initial expense
      create(:expense, email_account: email_account, amount: 100, transaction_date: Date.current)

      # Trigger job manually (in production this would be async)
      MetricsRefreshJob.new.perform(email_account.id, affected_dates: [ Date.current ])

      # Check metrics were calculated
      cache_key = "metrics_calculator:account_#{email_account.id}:day:#{Date.current.iso8601}"
      cached_data = Rails.cache.read(cache_key)

      expect(cached_data).not_to be_nil
      expect(cached_data[:metrics][:total_amount]).to eq(100.0)

      # Add another expense
      create(:expense, email_account: email_account, amount: 50, transaction_date: Date.current)

      # Clear cache to simulate refresh
      Rails.cache.delete(cache_key)

      # Refresh metrics
      MetricsRefreshJob.new.perform(email_account.id, affected_dates: [ Date.current ])

      # Check updated metrics
      cached_data = Rails.cache.read(cache_key)
      expect(cached_data[:metrics][:total_amount]).to eq(150.0)
    end

    it "prevents concurrent job execution" do
      # First job acquires lock
      lock_key = "metrics_calculation:#{email_account.id}"
      Rails.cache.write(lock_key, Time.current.to_s, expires_in: 5.minutes)

      # Second job should skip
      expect(Rails.logger).to receive(:info).with(/skipped - another job is already processing/)

      job = MetricsCalculationJob.new
      job.perform(email_account_id: email_account.id)
    end

    it "uses longer cache expiration for background-calculated metrics" do
      # Calculate metrics via background job
      job = MetricsCalculationJob.new
      job.perform(email_account_id: email_account.id, period: :month)

      # The ExtendedCacheMetricsCalculator should have been used
      cache_key = "metrics_calculator:account_#{email_account.id}:month:#{Date.current.iso8601}"
      cached_data = Rails.cache.read(cache_key)

      # Background-calculated flag indicates extended cache was used
      expect(cached_data[:background_calculated]).to be true
    end
  end

  describe "Performance monitoring" do
    it "tracks job execution metrics" do
      # Run job
      job = MetricsCalculationJob.new
      job.perform(email_account_id: email_account.id, period: :day)

      # Check metrics were tracked
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      metrics = Rails.cache.read(metrics_key)

      expect(metrics).not_to be_nil
      expect(metrics[:success_count]).to eq(1)
      expect(metrics[:executions]).not_to be_empty
      expect(metrics[:executions].first[:status]).to eq(:success)
    end

    it "monitors job health through MetricsJobMonitor" do
      # Simulate some job executions
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      Rails.cache.write(metrics_key, {
        success_count: 95,
        failure_count: 5,
        total_time: 1500.0,
        executions: []
      })

      # Check health status
      status = MetricsJobMonitor.status

      expect(status).to include(:health)
      expect(status[:health]).to include(:status, :message, :checks)
    end
  end

  describe "Error recovery" do
    it "releases lock on error" do
      lock_key = "metrics_calculation:#{email_account.id}"

      # Force an error
      allow_any_instance_of(ExtendedCacheMetricsCalculator).to receive(:calculate).and_raise(StandardError, "Test error")

      job = MetricsCalculationJob.new
      expect { job.perform(email_account_id: email_account.id, period: :month) }.to raise_error(StandardError)

      # Lock should be released
      expect(Rails.cache.read(lock_key)).to be_nil
    end

    it "tracks failure metrics" do
      # Force an error
      allow_any_instance_of(ExtendedCacheMetricsCalculator).to receive(:calculate).and_raise(StandardError, "Test error")

      job = MetricsCalculationJob.new
      expect { job.perform(email_account_id: email_account.id, period: :month) }.to raise_error(StandardError)

      # Check failure was tracked
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      metrics = Rails.cache.read(metrics_key)

      expect(metrics[:failure_count]).to eq(1)
    end
  end

  describe "Dashboard integration" do
    it "provides fast dashboard load with pre-calculated metrics" do
      # Pre-calculate all periods
      job = MetricsCalculationJob.new
      job.perform(email_account_id: email_account.id)

      # Simulate dashboard access - should use cached data
      calculator = MetricsCalculator.new(email_account: email_account, period: :month)

      # Measure performance
      start_time = Time.current
      result = calculator.calculate
      elapsed = Time.current - start_time

      # Should be very fast due to cache hit
      expect(elapsed).to be < 0.1 # Less than 100ms
      expect(result).not_to be_nil
    end
  end
end
