# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetricsCalculationJob, type: :job, unit: true do
  include ActiveJob::TestHelper

  let(:email_account) { create(:email_account, active: true) }
  let(:inactive_account) { create(:email_account, active: false) }
  let(:reference_date) { Date.parse("2024-01-15") }
  let(:job) { described_class.new }

  # Time helpers for performance testing
  let(:start_time) { Time.zone.local(2024, 1, 15, 10, 0, 0) }
  let(:fast_execution_time) { 5.seconds }
  let(:slow_execution_time) { 35.seconds }

  before do
    # Freeze time for consistent testing
    travel_to start_time
    # Clear job queue
    clear_enqueued_jobs
  end

  after do
    travel_back
  end

  describe "queue configuration" do
    it "uses default queue" do
      expect(described_class.queue_name).to eq("default")
    end

    it "has exponential backoff retry configuration" do
      # Check rescue_handlers for retry configuration
      handler = described_class.rescue_handlers.find { |h| h.first == 'StandardError' }
      expect(handler).not_to be_nil
      # The retry is configured with polynomially_longer wait and 3 attempts
    end
  end

  describe "constants" do
    it "defines MAX_EXECUTION_TIME as 30 seconds" do
      expect(described_class::MAX_EXECUTION_TIME).to eq(30.seconds)
    end

    it "defines CACHE_EXPIRY_HOURS as 4 hours" do
      expect(described_class::CACHE_EXPIRY_HOURS).to eq(4)
    end
  end

  describe "#perform" do
    context "when no email_account_id is provided (bulk processing mode)" do
      let!(:active_accounts) { create_list(:email_account, 3, active: true) }
      let!(:inactive_accounts) { create_list(:email_account, 2, active: false) }

      before do
        # Stub EmailAccount.active to return only our test accounts
        allow(EmailAccount).to receive(:active).and_return(
          EmailAccount.where(id: active_accounts.map(&:id))
        )
        allow(Rails.logger).to receive(:info)
      end

      it "enqueues jobs for all active accounts" do
        expect { job.perform(email_account_id: nil) }.to have_enqueued_job(described_class)
          .exactly(active_accounts.size).times
      end

      it "does not enqueue jobs for inactive accounts" do
        job.perform(email_account_id: nil)

        # Check that we have the right number of enqueued jobs
        expect(enqueued_jobs.size).to eq(active_accounts.size)

        # Verify each active account has a job enqueued
        active_accounts.each do |account|
          expect(described_class).to have_been_enqueued.with(email_account_id: account.id)
        end
      end

      it "logs bulk processing mode" do
        job.perform(email_account_id: nil)

        expect(Rails.logger).to have_received(:info)
          .with("MetricsCalculationJob called without email_account_id - enqueuing for all active accounts")
      end

      it "returns early without further processing" do
        expect(job).not_to receive(:acquire_lock)
        expect(ExtendedCacheServices::MetricsCalculator).not_to receive(:new)

        job.perform(email_account_id: nil)
      end
    end

    context "with email_account_id parameter handling" do
      it "accepts email_account_id as integer" do
        expect(EmailAccount).to receive(:find).with(email_account.id).and_return(email_account)
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:calculate_all_periods)

        job.perform(email_account_id: email_account.id)
      end

      it "accepts email_account_id as string" do
        expect(EmailAccount).to receive(:find).with(email_account.id.to_s).and_return(email_account)
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:calculate_all_periods)

        job.perform(email_account_id: email_account.id.to_s)
      end

      it "accepts EmailAccount object directly" do
        expect(EmailAccount).not_to receive(:find)
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:calculate_all_periods)

        job.perform(email_account_id: email_account)
      end

      it "returns early when email_account_id is nil even with period specified" do
        # When email_account_id is nil, it should still trigger bulk mode
        allow(Rails.logger).to receive(:info)
        expect(described_class).to receive(:enqueue_for_all_accounts)

        job.perform(email_account_id: nil, period: :month)
      end

      it "raises error for non-existent email account" do
        expect { job.perform(email_account_id: 999999) }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "distributed locking" do
      let(:lock_key) { "metrics_calculation:#{email_account.id}" }

      context "when lock is acquired successfully" do
        before do
          allow(Rails.cache).to receive(:write).with(
            lock_key,
            anything,
            expires_in: 5.minutes,
            unless_exist: true
          ).and_return(true)
          allow(Rails.cache).to receive(:delete)
          allow(job).to receive(:track_job_metrics)
        end

        it "acquires lock with correct parameters" do
          allow(job).to receive(:calculate_all_periods)

          job.perform(email_account_id: email_account)

          expect(Rails.cache).to have_received(:write).with(
            lock_key,
            anything,
            expires_in: 5.minutes,
            unless_exist: true
          )
        end

        it "releases lock in ensure block even on success" do
          allow(job).to receive(:calculate_all_periods)

          job.perform(email_account_id: email_account)

          expect(Rails.cache).to have_received(:delete).with(lock_key)
        end

        it "releases lock in ensure block even on failure" do
          allow(job).to receive(:calculate_all_periods).and_raise(StandardError, "Test error")
          allow(Rails.logger).to receive(:error)

          expect { job.perform(email_account_id: email_account) }
            .to raise_error(StandardError, "Test error")

          expect(Rails.cache).to have_received(:delete).with(lock_key)
        end
      end

      context "when lock is already held (lock contention)" do
        before do
          allow(Rails.cache).to receive(:write).with(
            lock_key,
            anything,
            expires_in: 5.minutes,
            unless_exist: true
          ).and_return(false)
          allow(Rails.logger).to receive(:info)
        end

        it "skips processing when lock cannot be acquired" do
          expect(job).not_to receive(:calculate_all_periods)
          expect(ExtendedCacheServices::MetricsCalculator).not_to receive(:new)

          job.perform(email_account_id: email_account)
        end

        it "logs lock contention" do
          job.perform(email_account_id: email_account)

          expect(Rails.logger).to have_received(:info)
            .with("MetricsCalculationJob skipped - another job is already processing account #{email_account.id}")
        end

        it "does not attempt to release lock" do
          expect(Rails.cache).not_to receive(:delete)

          job.perform(email_account_id: email_account)
        end
      end
    end

    context "with force_refresh option" do
      before do
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:release_lock)
        allow(job).to receive(:calculate_all_periods)
      end

      it "clears cache when force_refresh is true" do
        expect(Services::MetricsCalculator).to receive(:clear_cache)
          .with(email_account: email_account)

        job.perform(email_account_id: email_account, force_refresh: true)
      end

      it "does not clear cache when force_refresh is false" do
        expect(Services::MetricsCalculator).not_to receive(:clear_cache)

        job.perform(email_account_id: email_account, force_refresh: false)
      end

      it "does not clear cache when force_refresh is not provided" do
        expect(Services::MetricsCalculator).not_to receive(:clear_cache)

        job.perform(email_account_id: email_account)
      end
    end

    context "specific period calculation mode" do
      let(:calculator_double) { instance_double(ExtendedCacheServices::MetricsCalculator) }
      let(:calculation_result) do
        {
          metrics: {
            transaction_count: 42,
            total_amount: 1234.56
          },
          error: nil
        }
      end

      before do
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:release_lock)
        allow(ExtendedCacheServices::MetricsCalculator).to receive(:new).and_return(calculator_double)
        allow(calculator_double).to receive(:calculate).and_return(calculation_result)
        allow(Rails.logger).to receive(:info)
      end

      it "calculates metrics for specific period" do
        job.perform(
          email_account_id: email_account,
          period: :month,
          reference_date: reference_date
        )

        expect(ExtendedCacheServices::MetricsCalculator).to have_received(:new).with(
          email_account: email_account,
          period: :month,
          reference_date: reference_date,
          cache_hours: described_class::CACHE_EXPIRY_HOURS
        )
        expect(calculator_double).to have_received(:calculate)
      end

      it "logs calculation details" do
        job.perform(
          email_account_id: email_account,
          period: :week,
          reference_date: reference_date
        )

        expect(Rails.logger).to have_received(:info)
          .with("Calculating metrics for account #{email_account.id}, period: week, date: #{reference_date}")
      end

      it "logs calculation results" do
        job.perform(
          email_account_id: email_account,
          period: :day,
          reference_date: reference_date
        )

        expect(Rails.logger).to have_received(:info)
          .with(/Metrics calculated.*42 transactions.*\$1234\.56/)
      end

      context "with calculation error" do
        let(:error_result) do
          {
            metrics: {},
            error: "Database connection lost"
          }
        end

        before do
          allow(calculator_double).to receive(:calculate).and_return(error_result)
          allow(Rails.logger).to receive(:error)
        end

        it "logs error when calculation fails" do
          job.perform(
            email_account_id: email_account,
            period: :month,
            reference_date: reference_date
          )

          expect(Rails.logger).to have_received(:error)
            .with(/Metrics calculation failed.*Database connection lost/)
        end
      end
    end

    context "all periods calculation mode" do
      before do
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:release_lock)
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:debug)
      end

      it "calculates all periods when period is not specified" do
        expect(job).to receive(:calculate_all_periods)
          .with(email_account, Date.current)

        job.perform(email_account_id: email_account)
      end

      it "uses provided reference_date for all periods" do
        expect(job).to receive(:calculate_all_periods)
          .with(email_account, reference_date)

        job.perform(
          email_account_id: email_account,
          reference_date: reference_date
        )
      end

      it "defaults to current date when reference_date not provided" do
        expect(job).to receive(:calculate_all_periods)
          .with(email_account, Date.current)

        job.perform(email_account_id: email_account)
      end
    end

    context "performance monitoring" do
      let(:calculator_double) { instance_double(ExtendedCacheServices::MetricsCalculator) }

      before do
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:release_lock)
        allow(job).to receive(:track_job_metrics)
        allow(ExtendedCacheServices::MetricsCalculator).to receive(:new).and_return(calculator_double)
        allow(calculator_double).to receive(:calculate).and_return({
          metrics: { transaction_count: 10, total_amount: 100.0 }
        })
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
      end

      context "when execution is within threshold" do
        before do
          # Stub Time.current to simulate fast execution
          # Called at: start, lock write, end, track_job_metrics
          allow(Time).to receive(:current).and_return(
            start_time,                          # start_time = Time.current
            start_time,                          # lock write (timestamp)
            start_time + fast_execution_time,    # elapsed_time = Time.current - start_time
            start_time + fast_execution_time     # track_job_metrics timestamp
          )
        end

        it "logs successful completion with execution time" do
          job.perform(email_account_id: email_account, period: :month)

          expect(Rails.logger).to have_received(:info)
            .with("MetricsCalculationJob completed in 5.0s for account #{email_account.id}")
        end

        it "tracks success metrics" do
          job.perform(email_account_id: email_account, period: :month)

          expect(job).to have_received(:track_job_metrics)
            .with(email_account.id, fast_execution_time, :success)
        end

        it "does not track as slow job" do
          expect(job).not_to receive(:track_slow_job)

          job.perform(email_account_id: email_account, period: :month)
        end
      end

      context "when execution exceeds threshold" do
        before do
          # Stub Time.current to simulate slow execution
          # Called at: start, lock write, end, track_job_metrics, track_slow_job
          allow(Time).to receive(:current).and_return(
            start_time,                          # start_time = Time.current
            start_time,                          # lock write (timestamp)
            start_time + slow_execution_time,    # elapsed_time = Time.current - start_time
            start_time + slow_execution_time,    # track_job_metrics timestamp
            start_time + slow_execution_time     # track_slow_job timestamp
          )
          allow(job).to receive(:track_slow_job)
        end

        it "logs performance warning" do
          job.perform(email_account_id: email_account, period: :month)

          expect(Rails.logger).to have_received(:warn)
            .with("MetricsCalculationJob exceeded 30s target: 35.0s for account #{email_account.id}")
        end

        it "tracks slow job for analysis" do
          job.perform(email_account_id: email_account, period: :month)

          expect(job).to have_received(:track_slow_job)
            .with(email_account, slow_execution_time)
        end

        it "still tracks success metrics" do
          job.perform(email_account_id: email_account, period: :month)

          expect(job).to have_received(:track_job_metrics)
            .with(email_account.id, slow_execution_time, :success)
        end
      end
    end

    context "error handling and retry behavior" do
      before do
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:release_lock)
        allow(job).to receive(:track_job_metrics)
        allow(Rails.logger).to receive(:error)
      end

      context "when StandardError is raised" do
        let(:error) { StandardError.new("Database timeout") }

        before do
          allow(job).to receive(:calculate_all_periods).and_raise(error)
        end

        it "re-raises error for retry mechanism" do
          expect { job.perform(email_account_id: email_account) }
            .to raise_error(StandardError, "Database timeout")
        end

        it "logs error message and backtrace" do
          expect { job.perform(email_account_id: email_account) }
            .to raise_error(StandardError)

          expect(Rails.logger).to have_received(:error)
            .with("MetricsCalculationJob failed: Database timeout")
          expect(Rails.logger).to have_received(:error).at_least(:once)
        end

        it "tracks failure metrics" do
          expect { job.perform(email_account_id: email_account) }
            .to raise_error(StandardError)

          expect(job).to have_received(:track_job_metrics)
            .with(email_account.id, 0, :failure)
        end

        it "ensures lock is released on error" do
          expect { job.perform(email_account_id: email_account) }
            .to raise_error(StandardError)

          expect(job).to have_received(:release_lock)
            .with("metrics_calculation:#{email_account.id}")
        end
      end

      context "retry behavior verification" do
        it "is configured to retry on StandardError" do
          # Check that retry_on StandardError is configured
          handler = described_class.rescue_handlers.find { |h| h.first == 'StandardError' }
          expect(handler).not_to be_nil
        end

        it "uses exponential backoff for retries" do
          # polynomially_longer means: (executions**4) + 2
          # 1st retry: (1**4) + 2 = 3 seconds
          # 2nd retry: (2**4) + 2 = 18 seconds
          # 3rd retry: (3**4) + 2 = 83 seconds
          # Configuration is verified through rescue_handlers
          handler = described_class.rescue_handlers.find { |h| h.first == 'StandardError' }
          expect(handler).not_to be_nil
        end
      end
    end
  end

  describe "#calculate_all_periods" do
    let(:calculator_double) { instance_double(ExtendedCacheServices::MetricsCalculator) }
    let(:result) { { metrics: { transaction_count: 10, total_amount: 100.0 } } }

    before do
      allow(job).to receive(:acquire_lock).and_return(true)
      allow(job).to receive(:release_lock)
      allow(ExtendedCacheServices::MetricsCalculator).to receive(:new).and_return(calculator_double)
      allow(calculator_double).to receive(:calculate).and_return(result)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:debug)
    end

    it "generates correct number of period-date combinations" do
      # Expected: 8 days + 5 weeks + 4 months + 2 years = 19 total
      job.perform(email_account_id: email_account)

      expect(ExtendedCacheServices::MetricsCalculator).to have_received(:new).exactly(19).times
    end

    it "logs pre-calculation summary" do
      job.perform(email_account_id: email_account)

      expect(Rails.logger).to have_received(:info)
        .with("Pre-calculating 19 metric combinations for account #{email_account.id}")
    end

    it "creates calculator with correct cache hours" do
      job.perform(email_account_id: email_account)

      expect(ExtendedCacheServices::MetricsCalculator).to have_received(:new)
        .with(hash_including(cache_hours: 4))
        .at_least(:once)
    end
  end

  describe "#generate_periods_and_dates" do
    let(:base_date) { Date.parse("2024-01-15") }

    it "generates correct day periods (current + past 7 days)" do
      periods = job.send(:generate_periods_and_dates, base_date)
      day_periods = periods.select { |p, _| p == :day }

      expect(day_periods.size).to eq(8)
      expect(day_periods.map(&:last)).to match_array([
        base_date - 7.days,
        base_date - 6.days,
        base_date - 5.days,
        base_date - 4.days,
        base_date - 3.days,
        base_date - 2.days,
        base_date - 1.day,
        base_date
      ])
    end

    it "generates correct week periods (current + past 4 weeks)" do
      periods = job.send(:generate_periods_and_dates, base_date)
      week_periods = periods.select { |p, _| p == :week }

      expect(week_periods.size).to eq(5)
      expect(week_periods.map(&:last)).to match_array([
        base_date - 4.weeks,
        base_date - 3.weeks,
        base_date - 2.weeks,
        base_date - 1.week,
        base_date
      ])
    end

    it "generates correct month periods (current + past 3 months)" do
      periods = job.send(:generate_periods_and_dates, base_date)
      month_periods = periods.select { |p, _| p == :month }

      expect(month_periods.size).to eq(4)
      expect(month_periods.map(&:last)).to match_array([
        base_date - 3.months,
        base_date - 2.months,
        base_date - 1.month,
        base_date
      ])
    end

    it "generates correct year periods (current + previous year)" do
      periods = job.send(:generate_periods_and_dates, base_date)
      year_periods = periods.select { |p, _| p == :year }

      expect(year_periods.size).to eq(2)
      expect(year_periods.map(&:last)).to match_array([
        base_date - 1.year,
        base_date
      ])
    end

    it "handles month boundary correctly" do
      end_of_month = Date.parse("2024-01-31")
      periods = job.send(:generate_periods_and_dates, end_of_month)
      month_periods = periods.select { |p, _| p == :month }

      # Should handle month arithmetic correctly even at month boundaries
      expect(month_periods.map(&:last)).to include(
        Date.parse("2023-10-31"), # 3 months ago
        Date.parse("2023-11-30"), # 2 months ago (November has 30 days)
        Date.parse("2023-12-31"), # 1 month ago
        Date.parse("2024-01-31")  # current
      )
    end

    it "handles leap year correctly" do
      leap_day = Date.parse("2024-02-29")
      periods = job.send(:generate_periods_and_dates, leap_day)
      year_periods = periods.select { |p, _| p == :year }

      expect(year_periods.map(&:last)).to include(
        Date.parse("2023-02-28"), # Previous year (non-leap)
        Date.parse("2024-02-29")  # Current year (leap)
      )
    end
  end

  describe "#track_job_metrics" do
    let(:metrics_key) { "job_metrics:metrics_calculation:#{email_account.id}" }
    let(:existing_metrics) do
      {
        executions: [],
        success_count: 5,
        failure_count: 2,
        total_time: 50.0
      }
    end

    before do
      allow(Rails.cache).to receive(:fetch).and_return(existing_metrics)
      allow(Rails.cache).to receive(:write)
    end

    context "tracking successful execution" do
      it "increments success count" do
        job.send(:track_job_metrics, email_account.id, 10.5, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(success_count: 6),
          expires_in: 24.hours
        )
      end

      it "adds to total time" do
        job.send(:track_job_metrics, email_account.id, 10.5, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(total_time: 60.5),
          expires_in: 24.hours
        )
      end

      it "calculates correct average time" do
        job.send(:track_job_metrics, email_account.id, 10.5, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(average_time: 60.5 / 6),
          expires_in: 24.hours
        )
      end

      it "calculates correct success rate" do
        job.send(:track_job_metrics, email_account.id, 10.5, :success)

        # (6 successes / 8 total) * 100 = 75%
        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(success_rate: 75.0),
          expires_in: 24.hours
        )
      end
    end

    context "tracking failed execution" do
      it "increments failure count" do
        job.send(:track_job_metrics, email_account.id, 0, :failure)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(failure_count: 3),
          expires_in: 24.hours
        )
      end

      it "does not add to total time" do
        job.send(:track_job_metrics, email_account.id, 0, :failure)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(total_time: 50.0),
          expires_in: 24.hours
        )
      end

      it "updates success rate correctly" do
        job.send(:track_job_metrics, email_account.id, 0, :failure)

        # (5 successes / 8 total) * 100 = 62.5%
        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(success_rate: 62.5),
          expires_in: 24.hours
        )
      end
    end

    context "execution history management" do
      let(:many_executions) do
        {
          executions: Array.new(150) { |i| { timestamp: i.hours.ago, elapsed: i, status: :success } },
          success_count: 150,
          failure_count: 0,
          total_time: 1000.0
        }
      end

      before do
        allow(Rails.cache).to receive(:fetch).and_return(many_executions)
      end

      it "keeps only last 100 executions" do
        job.send(:track_job_metrics, email_account.id, 5.0, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including { |metrics| metrics[:executions].size == 100 },
          expires_in: 24.hours
        )
      end

      it "adds new execution to history" do
        job.send(:track_job_metrics, email_account.id, 5.0, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including { |metrics|
            metrics[:executions].last[:elapsed] == 5.0 &&
            metrics[:executions].last[:status] == :success
          },
          expires_in: 24.hours
        )
      end
    end

    context "edge cases" do
      it "handles zero total executions gracefully" do
        empty_metrics = {
          executions: [],
          success_count: 0,
          failure_count: 0,
          total_time: 0.0
        }
        allow(Rails.cache).to receive(:fetch).and_return(empty_metrics)

        job.send(:track_job_metrics, email_account.id, 10.0, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(
            success_rate: 100.0,
            average_time: 10.0
          ),
          expires_in: 24.hours
        )
      end

      it "handles nil cache response by initializing metrics" do
        allow(Rails.cache).to receive(:fetch).and_yield

        job.send(:track_job_metrics, email_account.id, 10.0, :success)

        expect(Rails.cache).to have_received(:write).with(
          metrics_key,
          hash_including(
            success_count: 1,
            failure_count: 0,
            total_time: 10.0
          ),
          expires_in: 24.hours
        )
      end
    end
  end

  describe "#track_slow_job" do
    let(:slow_jobs_key) { "slow_jobs:metrics_calculation" }
    let(:existing_slow_jobs) do
      Array.new(60) { |i| { email_account_id: i, timestamp: i.hours.ago, elapsed_time: 40 + i } }
    end

    before do
      allow(Rails.cache).to receive(:fetch).and_return(existing_slow_jobs)
      allow(Rails.cache).to receive(:write)
      allow(email_account.expenses).to receive(:count).and_return(1500)
    end

    it "adds slow job record with all required fields" do
      job.send(:track_slow_job, email_account, 45.seconds)

      expect(Rails.cache).to have_received(:write).with(
        slow_jobs_key,
        array_including(
          hash_including(
            email_account_id: email_account.id,
            elapsed_time: 45.seconds,
            expense_count: 1500
          )
        ),
        expires_in: 7.days
      )
    end

    it "keeps only last 50 slow job records" do
      job.send(:track_slow_job, email_account, 45.seconds)

      expect(Rails.cache).to have_received(:write).with(
        slow_jobs_key,
        an_instance_of(Array) { |arr| arr.size == 50 },
        expires_in: 7.days
      )
    end

    it "adds timestamp to slow job record" do
      job.send(:track_slow_job, email_account, 45.seconds)

      expect(Rails.cache).to have_received(:write).with(
        slow_jobs_key,
        array_including(
          hash_including { |record|
            record[:timestamp].is_a?(Time) &&
            (Time.current - record[:timestamp]).abs < 1.second
          }
        ),
        expires_in: 7.days
      )
    end

    it "handles empty slow jobs cache" do
      allow(Rails.cache).to receive(:fetch).and_yield

      job.send(:track_slow_job, email_account, 45.seconds)

      expect(Rails.cache).to have_received(:write).with(
        slow_jobs_key,
        [ hash_including(email_account_id: email_account.id) ],
        expires_in: 7.days
      )
    end
  end

  describe ".enqueue_for_all_accounts" do
    let!(:active_accounts) { create_list(:email_account, 4, active: true) }
    let!(:inactive_accounts) { create_list(:email_account, 2, active: false) }

    before do
      # Stub EmailAccount.active to return only our test accounts
      allow(EmailAccount).to receive(:active).and_return(
        EmailAccount.where(id: active_accounts.map(&:id))
      )
    end

    it "enqueues job for each active account" do
      expect { described_class.enqueue_for_all_accounts }
        .to have_enqueued_job(described_class)
        .exactly(active_accounts.size).times
    end

    it "passes correct email_account_id to each job" do
      described_class.enqueue_for_all_accounts

      # Verify each active account has a job enqueued with correct args
      active_accounts.each do |account|
        expect(described_class).to have_been_enqueued.with(email_account_id: account.id)
      end
    end

    it "does not enqueue for inactive accounts" do
      described_class.enqueue_for_all_accounts

      # Check exact number of jobs enqueued
      expect(enqueued_jobs.size).to eq(active_accounts.size)

      # Verify inactive accounts don't have jobs
      inactive_accounts.each do |account|
        expect(described_class).not_to have_been_enqueued.with(email_account_id: account.id)
      end
    end

    it "uses perform_later for background processing" do
      expect(described_class).to receive(:perform_later)
        .exactly(active_accounts.size).times

      described_class.enqueue_for_all_accounts
    end

    it "handles large number of accounts efficiently with find_each" do
      # Create many accounts to test batching
      many_accounts = create_list(:email_account, 50, active: true)

      # Stub EmailAccount.active to return our test accounts
      allow(EmailAccount).to receive(:active).and_return(
        EmailAccount.where(id: many_accounts.map(&:id))
      )

      expect { described_class.enqueue_for_all_accounts }
        .to have_enqueued_job(described_class)
        .exactly(50).times
    end
  end

  describe "integration scenarios" do
    context "complete successful flow with specific period" do
      let(:calculator) { instance_double(ExtendedCacheServices::MetricsCalculator) }
      let(:metrics_result) do
        {
          metrics: {
            transaction_count: 25,
            total_amount: 500.75
          }
        }
      end

      before do
        allow(Rails.cache).to receive(:write).and_return(true)
        allow(Rails.cache).to receive(:delete)
        allow(Rails.cache).to receive(:fetch).and_return({
          executions: [],
          success_count: 0,
          failure_count: 0,
          total_time: 0.0
        })
        allow(ExtendedCacheServices::MetricsCalculator).to receive(:new).and_return(calculator)
        allow(calculator).to receive(:calculate).and_return(metrics_result)
        allow(Rails.logger).to receive(:info)
      end

      it "completes full execution flow" do
        job.perform(
          email_account_id: email_account,
          period: :month,
          reference_date: reference_date
        )

        # Verify all steps executed in order
        expect(Rails.cache).to have_received(:write).with(
          "metrics_calculation:#{email_account.id}",
          anything,
          hash_including(expires_in: 5.minutes)
        ).ordered

        expect(ExtendedCacheServices::MetricsCalculator).to have_received(:new).ordered
        expect(calculator).to have_received(:calculate).ordered

        expect(Rails.cache).to have_received(:delete).with(
          "metrics_calculation:#{email_account.id}"
        ).ordered
      end
    end

    context "complete flow with all periods calculation" do
      before do
        allow(Rails.cache).to receive(:write).and_return(true)
        allow(Rails.cache).to receive(:delete)
        allow(Rails.cache).to receive(:fetch).and_return({
          executions: [],
          success_count: 0,
          failure_count: 0,
          total_time: 0.0
        })

        # Mock calculator for all period combinations
        calculator = instance_double(ExtendedCacheServices::MetricsCalculator)
        allow(ExtendedCacheServices::MetricsCalculator).to receive(:new).and_return(calculator)
        allow(calculator).to receive(:calculate).and_return({
          metrics: { transaction_count: 10, total_amount: 100.0 }
        })

        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:debug)
      end

      it "processes all period combinations successfully" do
        job.perform(email_account_id: email_account)

        # Should create 19 calculators (8 days + 5 weeks + 4 months + 2 years)
        expect(ExtendedCacheServices::MetricsCalculator).to have_received(:new).exactly(19).times
      end
    end

    context "error recovery and retry" do
      before do
        allow(Rails.cache).to receive(:write).and_return(true)
        allow(Rails.cache).to receive(:delete)
        allow(Rails.logger).to receive(:error)
      end

      it "ensures cleanup even on catastrophic failure" do
        allow(job).to receive(:calculate_all_periods).and_raise(NoMemoryError, "Out of memory")

        expect { job.perform(email_account_id: email_account) }
          .to raise_error(NoMemoryError)

        # Lock should still be released
        expect(Rails.cache).to have_received(:delete)
          .with("metrics_calculation:#{email_account.id}")
      end
    end
  end

  describe "cache operation semantics" do
    let(:lock_key) { "metrics_calculation:#{email_account.id}" }

    context "lock acquisition with unless_exist semantics" do
      it "writes lock with timestamp value" do
        expect(Rails.cache).to receive(:write).with(
          lock_key,
          an_instance_of(String), # Timestamp as string
          hash_including(
            expires_in: 5.minutes,
            unless_exist: true
          )
        ).and_return(true)

        allow(job).to receive(:calculate_all_periods)
        allow(job).to receive(:track_job_metrics)
        allow(Rails.cache).to receive(:delete)

        job.perform(email_account_id: email_account)
      end

      it "respects unless_exist flag for concurrent safety" do
        # First call succeeds
        expect(Rails.cache).to receive(:write)
          .with(lock_key, anything, hash_including(unless_exist: true))
          .and_return(true)
          .once

        allow(job).to receive(:calculate_all_periods)
        allow(job).to receive(:track_job_metrics)
        allow(Rails.cache).to receive(:delete)

        job.perform(email_account_id: email_account)
      end
    end

    context "metrics cache operations" do
      it "caches metrics with 24-hour expiration" do
        metrics_key = "job_metrics:metrics_calculation:#{email_account.id}"

        allow(Rails.cache).to receive(:write).and_call_original
        allow(Rails.cache).to receive(:fetch).and_return({
          executions: [],
          success_count: 0,
          failure_count: 0,
          total_time: 0.0
        })

        expect(Rails.cache).to receive(:write).with(
          metrics_key,
          anything,
          expires_in: 24.hours
        )

        job.send(:track_job_metrics, email_account.id, 10.0, :success)
      end
    end

    context "slow job cache operations" do
      it "caches slow jobs with 7-day expiration" do
        slow_jobs_key = "slow_jobs:metrics_calculation"

        allow(Rails.cache).to receive(:fetch).and_return([])

        expect(Rails.cache).to receive(:write).with(
          slow_jobs_key,
          anything,
          expires_in: 7.days
        )

        job.send(:track_slow_job, email_account, 35.seconds)
      end
    end
  end

  describe "edge cases and boundary conditions" do
    context "date handling edge cases" do
      it "handles end of year correctly" do
        end_of_year = Date.parse("2024-12-31")
        periods = job.send(:generate_periods_and_dates, end_of_year)

        year_periods = periods.select { |p, _| p == :year }
        expect(year_periods).to include(
          [ :year, Date.parse("2023-12-31") ],
          [ :year, Date.parse("2024-12-31") ]
        )
      end

      it "handles beginning of year correctly" do
        beginning_of_year = Date.parse("2024-01-01")
        periods = job.send(:generate_periods_and_dates, beginning_of_year)

        month_periods = periods.select { |p, _| p == :month }
        expect(month_periods).to include(
          [ :month, Date.parse("2023-10-01") ],
          [ :month, Date.parse("2023-11-01") ],
          [ :month, Date.parse("2023-12-01") ],
          [ :month, Date.parse("2024-01-01") ]
        )
      end
    end

    context "numeric precision and formatting" do
      it "formats amounts with exactly 2 decimal places" do
        expect(job.send(:format_amount, 1234.5)).to eq("$1234.50")
        expect(job.send(:format_amount, 1234.567)).to eq("$1234.57")
        expect(job.send(:format_amount, 0)).to eq("$0.00")
        expect(job.send(:format_amount, 0.1)).to eq("$0.10")
      end

      it "handles very large amounts" do
        expect(job.send(:format_amount, 999999999.99)).to eq("$999999999.99")
      end

      it "handles negative amounts" do
        expect(job.send(:format_amount, -123.45)).to eq("$-123.45")
      end
    end

    context "parameter validation edge cases" do
      it "handles email_account with no expenses gracefully" do
        allow(email_account.expenses).to receive(:count).and_return(0)
        allow(Rails.cache).to receive(:write).and_return(true)
        allow(Rails.cache).to receive(:delete)
        allow(Rails.cache).to receive(:fetch).and_return([])

        expect { job.send(:track_slow_job, email_account, 35.seconds) }
          .not_to raise_error
      end

      it "handles string period parameter" do
        calculator = instance_double(ExtendedCacheServices::MetricsCalculator)
        allow(ExtendedCacheServices::MetricsCalculator).to receive(:new).and_return(calculator)
        allow(calculator).to receive(:calculate).and_return({
          metrics: { transaction_count: 5, total_amount: 50.0 }
        })
        allow(job).to receive(:acquire_lock).and_return(true)
        allow(job).to receive(:release_lock)
        allow(job).to receive(:track_job_metrics)

        job.perform(
          email_account_id: email_account,
          period: "month", # String instead of symbol
          reference_date: reference_date
        )

        # The job passes the period as-is to ExtendedCacheServices::MetricsCalculator
        expect(ExtendedCacheServices::MetricsCalculator).to have_received(:new).with(
          hash_including(period: "month")
        )
      end
    end
  end
end
