# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetricsJobMonitor do
  let(:email_account) { create(:email_account) }

  before do
    Rails.cache.clear
  end

  describe '.status' do
    it 'returns comprehensive job status' do
      status = described_class.status

      expect(status).to include(
        :calculation_jobs,
        :refresh_jobs,
        :performance,
        :health,
        :slow_jobs,
        :recommendations
      )
    end
  end

  describe '.calculation_job_status' do
    it 'aggregates metrics across all accounts' do
      # Simulate job metrics for multiple accounts
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      Rails.cache.write(metrics_key, {
        success_count: 10,
        failure_count: 1,
        total_time: 150.0,
        executions: [
          { timestamp: 1.hour.ago, elapsed: 15.0, status: :success }
        ]
      })

      status = described_class.calculation_job_status

      expect(status[:total_executions]).to eq(11)
      expect(status[:success_rate]).to be > 90
      expect(status[:average_execution_time]).to eq(15.0)
    end

    it 'determines correct job status based on metrics' do
      # Simulate moderate failure rate that should trigger warning
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      Rails.cache.write(metrics_key, {
        success_count: 18,
        failure_count: 2,
        total_time: 100.0,
        executions: []
      })

      status = described_class.calculation_job_status

      # 18 success out of 20 total = 90% success rate
      # This should trigger warning (10% failure rate, between 5% and 10% thresholds)
      expect(status[:status]).to eq(:warning)
    end
  end

  describe '.refresh_job_status' do
    it 'includes debounced job count' do
      # Simulate debounced job
      job_key = "metrics_refresh_debounce:#{email_account.id}:#{(Time.current.to_i / 60)}"
      Rails.cache.write(job_key, true)

      status = described_class.refresh_job_status

      expect(status[:debounced_count]).to be >= 1
    end
  end

  describe '.performance_metrics' do
    it 'calculates overall performance metrics' do
      # Set up test metrics
      calc_metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      refresh_metrics_key = "job_metrics:metrics_refresh:#{email_account.id}"

      Rails.cache.write(calc_metrics_key, {
        success_count: 10,
        failure_count: 0,
        total_time: 200.0,
        executions: [
          { timestamp: 30.minutes.ago, elapsed: 20.0, status: :success },
          { timestamp: 1.hour.ago, elapsed: 35.0, status: :success } # Slow job
        ]
      })

      Rails.cache.write(refresh_metrics_key, {
        success_count: 5,
        failure_count: 0,
        total_time: 50.0,
        executions: [
          { timestamp: 20.minutes.ago, elapsed: 10.0, status: :success }
        ]
      })

      metrics = described_class.performance_metrics

      expect(metrics[:total_metric_calculations]).to eq(15)
      expect(metrics[:average_execution_time]).to be > 0
      expect(metrics[:jobs_exceeding_target]).to eq(1) # One job at 35s
    end
  end

  describe '.health_check' do
    context 'with healthy metrics' do
      it 'returns healthy status' do
        # Set up healthy metrics for both calculation and refresh jobs
        calc_metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
        Rails.cache.write(calc_metrics_key, {
          success_count: 100,
          failure_count: 2,
          total_time: 1500.0,
          executions: []
        })

        refresh_metrics_key = "job_metrics:metrics_refresh:#{email_account.id}"
        Rails.cache.write(refresh_metrics_key, {
          success_count: 50,
          failure_count: 1,
          total_time: 600.0,
          executions: []
        })

        health = described_class.health_check

        expect(health[:status]).to eq(:healthy)
        expect(health[:checks][:calculation_job_healthy]).to be true
      end
    end

    context 'with high failure rate' do
      it 'returns critical status' do
        # Set up metrics with high failure rate
        metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
        Rails.cache.write(metrics_key, {
          success_count: 80,
          failure_count: 25, # > 10% failure rate
          total_time: 1500.0,
          executions: []
        })

        health = described_class.health_check

        expect(health[:status]).to eq(:critical)
        expect(health[:message]).to include("High failure rate")
      end
    end

    context 'with slow performance' do
      it 'returns warning status' do
        # Set up metrics with slow average time but healthy refresh metrics
        calc_metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
        Rails.cache.write(calc_metrics_key, {
          success_count: 10,
          failure_count: 0,
          total_time: 350.0, # Average 35s per job
          executions: []
        })

        # Add healthy refresh metrics so only calculation triggers warning
        refresh_metrics_key = "job_metrics:metrics_refresh:#{email_account.id}"
        Rails.cache.write(refresh_metrics_key, {
          success_count: 20,
          failure_count: 0,
          total_time: 200.0, # Average 10s per job (healthy)
          executions: []
        })

        health = described_class.health_check

        expect(health[:status]).to eq(:warning)
        expect(health[:message]).to include("exceeding performance target")
      end
    end
  end

  describe '.recent_slow_jobs' do
    it 'returns recent slow job executions' do
      # Add slow job to cache
      slow_jobs_key = "slow_jobs:metrics_calculation"
      Rails.cache.write(slow_jobs_key, [
        {
          email_account_id: email_account.id,
          timestamp: 1.hour.ago,
          elapsed_time: 45.0,
          expense_count: 5000
        }
      ])

      slow_jobs = described_class.recent_slow_jobs

      expect(slow_jobs).not_to be_empty
      expect(slow_jobs.first[:elapsed_time]).to eq(45.0)
      expect(slow_jobs.first[:exceeded_by]).to eq(15.0) # 45 - 30 = 15
    end
  end

  describe '.clear_stale_locks' do
    it 'clears locks older than 10 minutes' do
      # Create stale lock
      lock_key = "metrics_calculation:#{email_account.id}"
      Rails.cache.write(lock_key, 15.minutes.ago.to_s)

      cleared = described_class.clear_stale_locks

      expect(cleared).to eq(1)
      expect(Rails.cache.read(lock_key)).to be_nil
    end

    it 'preserves recent locks' do
      # Create recent lock
      lock_key = "metrics_calculation:#{email_account.id}"
      Rails.cache.write(lock_key, 5.minutes.ago.to_s)

      cleared = described_class.clear_stale_locks

      expect(cleared).to eq(0)
      expect(Rails.cache.read(lock_key)).not_to be_nil
    end
  end

  describe '.force_recalculate_all' do
    it 'enqueues jobs for all active accounts' do
      expect(MetricsCalculationJob).to receive(:perform_later).with(
        email_account_id: email_account.id,
        force_refresh: true
      )

      described_class.force_recalculate_all
    end
  end

  describe 'recommendations' do
    it 'generates performance recommendations for slow jobs' do
      # Set up slow average execution time
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      Rails.cache.write(metrics_key, {
        success_count: 10,
        failure_count: 0,
        total_time: 350.0, # Average 35s
        executions: []
      })

      status = described_class.status
      recommendations = status[:recommendations]

      expect(recommendations).to be_an(Array)
      expect(recommendations.any? { |r| r[:type] == :performance }).to be true
    end

    it 'generates reliability recommendations for high failure rates' do
      # Set up high failure rate
      metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"
      Rails.cache.write(metrics_key, {
        success_count: 90,
        failure_count: 15,
        total_time: 1500.0,
        executions: []
      })

      status = described_class.status
      recommendations = status[:recommendations]

      expect(recommendations.any? { |r| r[:type] == :reliability }).to be true
    end

    it 'generates maintenance recommendations for stale locks' do
      # Create stale lock
      lock_key = "metrics_calculation:#{email_account.id}"
      Rails.cache.write(lock_key, 15.minutes.ago.to_s)

      status = described_class.status
      recommendations = status[:recommendations]

      expect(recommendations.any? { |r| r[:type] == :maintenance }).to be true
    end
  end
end
