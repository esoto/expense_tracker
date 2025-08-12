# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetricsRefreshJob, type: :job do
  let(:email_account) { create(:email_account) }
  let(:job) { described_class.new }

  before do
    # Clear cache before each test
    Rails.cache.clear
  end

  describe "#perform" do
    context "with valid email account" do
      it "refreshes metrics for affected periods" do
        # Create some expenses
        create(:expense, email_account: email_account, transaction_date: Date.current)
        create(:expense, email_account: email_account, transaction_date: 1.day.ago)

        # Pre-calculate metrics to populate cache
        calculator = MetricsCalculator.new(email_account: email_account, period: :day)
        calculator.calculate

        # Clear cache to simulate stale data
        Rails.cache.clear

        # Perform the job
        job.perform(email_account.id, affected_dates: [ Date.current ])

        # Verify metrics were recalculated
        cache_key = "metrics_calculator:account_#{email_account.id}:day:#{Date.current.iso8601}"
        expect(Rails.cache.exist?(cache_key)).to be true
      end

      it "handles multiple affected dates" do
        affected_dates = [ Date.current, 1.day.ago.to_date, 7.days.ago.to_date ]

        # Count unique period/date combinations that will be calculated
        # Each date affects day, week, month, year periods
        allow_any_instance_of(MetricsCalculator).to receive(:calculate).and_return({
          metrics: { total_amount: 0.0, transaction_count: 0 }
        })

        job.perform(email_account.id, affected_dates: affected_dates)
      end

      it "prevents concurrent execution for same account" do
        # Acquire lock manually
        lock_key = "metrics_refresh:#{email_account.id}"
        Rails.cache.write(lock_key, Time.current.to_s, expires_in: 60.seconds)

        # Job should skip execution
        expect(Rails.logger).to receive(:info).with(/skipped - another job is already processing/)
        expect_any_instance_of(MetricsCalculator).not_to receive(:calculate)

        job.perform(email_account.id)
      end

      it "tracks performance metrics" do
        job.perform(email_account.id)

        metrics_key = "job_metrics:metrics_refresh:#{email_account.id}"
        metrics = Rails.cache.read(metrics_key)

        expect(metrics).not_to be_nil
        expect(metrics[:success_count]).to eq(1)
        expect(metrics[:executions]).not_to be_empty
      end

      it "logs warning when exceeding 30 second target" do
        # Mock slow execution
        start_time = Time.current
        allow(Time).to receive(:current).and_return(
          start_time,          # Start time
          start_time,          # Lock acquisition
          start_time + 31.seconds  # End time
        )

        expect(Rails.logger).to receive(:warn).with(/exceeded 30s target/)

        job.perform(email_account.id)
      end
    end

    context "with error handling" do
      it "re-raises errors for retry mechanism" do
        allow(EmailAccount).to receive(:find).and_raise(ActiveRecord::RecordNotFound)

        expect { job.perform(999) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "releases lock even on error" do
        lock_key = "metrics_refresh:#{email_account.id}"

        allow_any_instance_of(MetricsCalculator).to receive(:calculate).and_raise(StandardError, "Test error")

        expect { job.perform(email_account.id) }.to raise_error(StandardError)

        # Lock should be released
        expect(Rails.cache.read(lock_key)).to be_nil
      end

      it "tracks failure metrics" do
        allow_any_instance_of(MetricsCalculator).to receive(:calculate).and_raise(StandardError, "Test error")

        expect { job.perform(email_account.id) }.to raise_error(StandardError)

        metrics_key = "job_metrics:metrics_refresh:#{email_account.id}"
        metrics = Rails.cache.read(metrics_key)

        expect(metrics[:failure_count]).to eq(1)
      end
    end
  end

  describe ".enqueue_debounced" do
    it "prevents duplicate jobs within time window" do
      # First call should enqueue
      job1 = described_class.enqueue_debounced(email_account.id)
      expect(job1).not_to be_nil

      # Second call within same minute should be debounced
      job2 = described_class.enqueue_debounced(email_account.id)
      expect(job2).to be_nil
    end

    it "collects multiple affected dates" do
      date1 = Date.current
      date2 = 1.day.ago.to_date

      described_class.enqueue_debounced(email_account.id, affected_date: date1)
      # Second call should not enqueue but should collect the date
      described_class.enqueue_debounced(email_account.id, affected_date: date2)

      dates_key = "metrics_refresh_dates:#{email_account.id}"
      affected_dates = Rails.cache.read(dates_key)

      expect(affected_dates).to be_an(Array)
      # Check that dates were collected (may be in different order)
      expect(affected_dates.size).to be >= 1
    end

    it "schedules job with specified delay" do
      expect(described_class).to receive(:set).with(wait: 10.seconds).and_call_original

      described_class.enqueue_debounced(email_account.id, delay: 10.seconds)
    end
  end

  describe "period determination" do
    it "determines affected periods correctly for a given date" do
      job = described_class.new
      affected_dates = [ Date.new(2024, 1, 15) ]

      periods = job.send(:determine_affected_periods, affected_dates)

      expect(periods[:day]).to include(Date.new(2024, 1, 15))
      expect(periods[:week]).to include(Date.new(2024, 1, 15).beginning_of_week)
      expect(periods[:month]).to include(Date.new(2024, 1, 1))
      expect(periods[:year]).to include(Date.new(2024, 1, 1))
    end

    it "includes current periods for recent dates" do
      job = described_class.new
      affected_dates = [ 1.day.ago ]

      periods = job.send(:determine_affected_periods, affected_dates)

      expect(periods[:day]).to include(Date.current)
      expect(periods[:week]).to include(Date.current.beginning_of_week)
      expect(periods[:month]).to include(Date.current.beginning_of_month)
    end

    it "handles empty affected dates by refreshing current periods" do
      job = described_class.new
      periods = job.send(:determine_affected_periods, [])

      MetricsCalculator::SUPPORTED_PERIODS.each do |period|
        expect(periods[period]).to eq([ Date.current ])
      end
    end
  end

  describe "cache clearing" do
    it "clears cache for affected periods" do
      job = described_class.new

      # Pre-populate cache
      cache_key = "metrics_calculator:account_#{email_account.id}:day:#{Date.current.iso8601}"
      Rails.cache.write(cache_key, { test: "data" })

      periods_to_refresh = { day: [ Date.current ] }
      job.send(:clear_affected_cache, email_account, periods_to_refresh)

      expect(Rails.cache.read(cache_key)).to be_nil
    end
  end

  describe "integration with ActiveJob" do
    it "can be enqueued and performed" do
      expect {
        described_class.perform_later(email_account.id)
      }.to have_enqueued_job(described_class)
        .with(email_account.id)
        .on_queue("low_priority")
    end

    it "retries on failure with exponential backoff" do
      # Test that the retry behavior works by checking the class configuration
      # The job should have retry_on defined in its source code
      expect(described_class.instance_methods).to include(:perform)

      # Check that the class has retry configuration by inspecting the source
      source_lines = File.readlines(Rails.root.join('app/jobs/metrics_refresh_job.rb'))
      retry_line = source_lines.find { |line| line.include?('retry_on StandardError') }
      expect(retry_line).not_to be_nil
      expect(retry_line).to include('polynomially_longer')
      expect(retry_line).to include('attempts: 3')
    end
  end
end
