# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/monitoring_service_test_helper"

RSpec.describe Services::Infrastructure::MonitoringService::JobMonitor, type: :service, unit: true do
  include MonitoringServiceTestHelper

  let(:job_monitor) { described_class }

  before do
    setup_time_helpers
    @mocked_models = mock_solid_queue_models
  end

  describe ".metrics" do
    it "returns complete metrics structure" do
      # Mock all sub-methods to avoid real database calls and division errors
      allow(job_monitor).to receive(:total_jobs_count).and_return(100)
      allow(job_monitor).to receive(:jobs_by_status).and_return({ pending: 10, processing: 5, finished: 80, failed: 5 })
      allow(job_monitor).to receive(:jobs_by_class).and_return({ "ProcessEmailJob" => 50 })
      allow(job_monitor).to receive(:average_wait_time).and_return(2.5)
      allow(job_monitor).to receive(:average_execution_time).and_return(15.75)
      allow(job_monitor).to receive(:calculate_failure_rate).and_return(5.0)

      result = job_monitor.metrics

      expect_metric_structure(result, [
        :total_jobs,
        :jobs_by_status,
        :jobs_by_class,
        :average_wait_time,
        :average_execution_time,
        :failure_rate
      ])
    end

    it "aggregates all job monitoring data" do
      # Setup specific expectations
      allow(job_monitor).to receive(:total_jobs_count).and_return(100)
      allow(job_monitor).to receive(:jobs_by_status).and_return({ pending: 10, processing: 5, finished: 80, failed: 5 })
      allow(job_monitor).to receive(:jobs_by_class).and_return({ "ProcessEmailJob" => 50, "MetricsJob" => 30 })
      allow(job_monitor).to receive(:average_wait_time).and_return(2.5)
      allow(job_monitor).to receive(:average_execution_time).and_return(15.75)
      allow(job_monitor).to receive(:calculate_failure_rate).and_return(5.0)

      result = job_monitor.metrics

      expect(result[:total_jobs]).to eq(100)
      expect(result[:jobs_by_status]).to eq({ pending: 10, processing: 5, finished: 80, failed: 5 })
      expect(result[:jobs_by_class]).to eq({ "ProcessEmailJob" => 50, "MetricsJob" => 30 })
      expect(result[:average_wait_time]).to eq(2.5)
      expect(result[:average_execution_time]).to eq(15.75)
      expect(result[:failure_rate]).to eq(5.0)
    end
  end

  describe ".total_jobs_count" do
    context "with jobs in the last hour" do
      it "counts jobs created within the time window" do
        expect(@mocked_models[:job]).to receive(:where)
          .with(created_at: one_hour_ago..current_time)
          .and_return(@mocked_models[:job])

        allow(@mocked_models[:job]).to receive(:count).and_return(42)

        result = job_monitor.total_jobs_count

        expect(result).to eq(42)
      end
    end

    context "with no recent jobs" do
      it "returns zero" do
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count)
          .and_return(0)

        result = job_monitor.total_jobs_count

        expect(result).to eq(0)
      end
    end

    context "with many jobs" do
      it "returns accurate count" do
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count)
          .and_return(1_250)

        result = job_monitor.total_jobs_count

        expect(result).to eq(1_250)
      end
    end
  end

  describe ".jobs_by_status" do
    context "with jobs in various states" do
      it "returns counts for all status types" do
        # Setup individual scopes
        pending_scope = double("pending_scope", count: 15)
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        finished_scope = double("finished_scope", count: 200)

        allow(@mocked_models[:job]).to receive(:pending).and_return(pending_scope)
        allow(@mocked_models[:job]).to receive(:where).with(finished_at: nil).and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(double(count: 8))
        allow(@mocked_models[:job]).to receive(:finished).and_return(finished_scope)
        allow(@mocked_models[:failed]).to receive(:count).and_return(12)

        result = job_monitor.jobs_by_status

        expect(result).to eq({
          pending: 15,
          processing: 8,
          finished: 200,
          failed: 12
        })
      end
    end

    context "with no jobs" do
      it "returns zeros for all statuses" do
        allow(@mocked_models[:job]).to receive(:pending).and_return(double(count: 0))
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        allow(@mocked_models[:job]).to receive(:where).with(finished_at: nil).and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(double(count: 0))
        allow(@mocked_models[:job]).to receive(:finished).and_return(double(count: 0))
        allow(@mocked_models[:failed]).to receive(:count).and_return(0)

        result = job_monitor.jobs_by_status

        expect(result[:pending]).to eq(0)
        expect(result[:processing]).to eq(0)
        expect(result[:finished]).to eq(0)
        expect(result[:failed]).to eq(0)
      end
    end

    context "with complex processing state logic" do
      it "correctly identifies processing jobs (claimed but not finished)" do
        # Processing jobs are those with claimed_at but no finished_at
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        allow(@mocked_models[:job]).to receive(:where).with(finished_at: nil).and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(double(count: 3))

        allow(@mocked_models[:job]).to receive(:pending).and_return(double(count: 0))
        allow(@mocked_models[:job]).to receive(:finished).and_return(double(count: 0))
        allow(@mocked_models[:failed]).to receive(:count).and_return(0)

        result = job_monitor.jobs_by_status

        expect(result[:processing]).to eq(3)
      end
    end
  end

  describe ".jobs_by_class" do
    context "with multiple job classes" do
      it "groups jobs by class name and sorts by count descending" do
        job_counts = {
          "ProcessEmailJob" => 100,
          "MetricsCalculationJob" => 50,
          "SyncSessionJob" => 25,
          "NotificationJob" => 10
        }

        scope_chain = double("scope_chain")
        allow(@mocked_models[:job]).to receive(:where)
          .with(created_at: one_hour_ago..current_time)
          .and_return(scope_chain)
        allow(scope_chain).to receive(:group).with(:class_name).and_return(scope_chain)
        allow(scope_chain).to receive(:count).and_return(job_counts)

        result = job_monitor.jobs_by_class

        # Should be sorted by count descending
        expect(result.keys).to eq([ "ProcessEmailJob", "MetricsCalculationJob", "SyncSessionJob", "NotificationJob" ])
        expect(result["ProcessEmailJob"]).to eq(100)
        expect(result["NotificationJob"]).to eq(10)
      end
    end

    context "with no recent jobs" do
      it "returns empty hash" do
        scope_chain = double("scope_chain")
        allow(@mocked_models[:job]).to receive(:where).and_return(scope_chain)
        allow(scope_chain).to receive(:group).and_return(scope_chain)
        allow(scope_chain).to receive(:count).and_return({})

        result = job_monitor.jobs_by_class

        expect(result).to eq({})
      end
    end

    context "with single job class" do
      it "returns single class count" do
        job_counts = { "ProcessEmailJob" => 15 }

        scope_chain = double("scope_chain")
        allow(@mocked_models[:job]).to receive(:where).and_return(scope_chain)
        allow(scope_chain).to receive(:group).and_return(scope_chain)
        allow(scope_chain).to receive(:count).and_return(job_counts)

        result = job_monitor.jobs_by_class

        expect(result).to eq({ "ProcessEmailJob" => 15 })
      end
    end
  end

  describe ".average_wait_time" do
    context "with finished jobs that have wait times" do
      it "calculates average wait time from created_at to claimed_at" do
        # Mock finished jobs with timestamps
        jobs_scope = double("jobs_scope")
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        final_scope = double("final_scope")

        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where)
          .with(finished_at: one_hour_ago..current_time)
          .and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(final_scope)
        allow(final_scope).to receive(:empty?).and_return(false)

        # Mock timestamp data: jobs waited 10s, 20s, 30s
        timestamp_data = [
          [ Time.current - 60, Time.current - 50 ], # 10 second wait
          [ Time.current - 50, Time.current - 30 ], # 20 second wait
          [ Time.current - 40, Time.current - 10 ]  # 30 second wait
        ]
        allow(final_scope).to receive(:pluck).with(:created_at, :claimed_at).and_return(timestamp_data)

        result = job_monitor.average_wait_time

        # Average of 10, 20, 30 = 20 seconds
        expect(result).to eq(20.0)
      end
    end

    context "with no finished jobs" do
      it "returns zero" do
        jobs_scope = double("jobs_scope")
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        final_scope = double("final_scope", empty?: true)

        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(final_scope)

        result = job_monitor.average_wait_time

        expect(result).to eq(0)
      end
    end

    context "with jobs having no claimed timestamp" do
      it "fails when trying to calculate with nil claimed_at values" do
        jobs_scope = double("jobs_scope")
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        final_scope = double("final_scope")

        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(final_scope)
        allow(final_scope).to receive(:empty?).and_return(false)

        # Some jobs never got claimed (nil claimed_at) - this will cause an error in the current implementation
        timestamp_data = [
          [ Time.current - 60, nil ],
          [ Time.current - 50, Time.current - 30 ]
        ]
        allow(final_scope).to receive(:pluck).and_return(timestamp_data)

        expect { job_monitor.average_wait_time }.to raise_error(NoMethodError)
      end
    end

    context "with precise wait time calculations" do
      it "rounds result to 2 decimal places" do
        jobs_scope = double("jobs_scope")
        where_chain = double("where_chain")
        not_scope = double("not_scope")
        final_scope = double("final_scope")

        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(where_chain)
        allow(where_chain).to receive(:where).and_return(not_scope)
        allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(final_scope)
        allow(final_scope).to receive(:empty?).and_return(false)

        # Wait times that create non-round average
        timestamp_data = [
          [ Time.current - 60, Time.current - 55.333 ], # 4.667 second wait
          [ Time.current - 50, Time.current - 45.111 ]  # 4.889 second wait
        ]
        allow(final_scope).to receive(:pluck).and_return(timestamp_data)

        result = job_monitor.average_wait_time

        # Should be rounded to 2 decimal places
        expect(result).to be_a(Float)
        expect(result.to_s.split('.').last.length).to be <= 2
      end
    end
  end

  describe ".average_execution_time" do
    context "with finished jobs that have execution times" do
      it "calculates average execution time from claimed_at to finished_at" do
        jobs_scope = double("jobs_scope")
        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where)
          .with(finished_at: one_hour_ago..current_time)
          .and_return(jobs_scope)
        allow(jobs_scope).to receive(:empty?).and_return(false)

        # Mock execution time data: jobs took 5s, 10s, 15s
        timestamp_data = [
          [ Time.current - 50, Time.current - 45 ], # 5 second execution
          [ Time.current - 40, Time.current - 30 ], # 10 second execution
          [ Time.current - 25, Time.current - 10 ]  # 15 second execution
        ]
        allow(jobs_scope).to receive(:pluck).with(:claimed_at, :finished_at).and_return(timestamp_data)

        result = job_monitor.average_execution_time

        # Average of 5, 10, 15 = 10 seconds
        expect(result).to eq(10.0)
      end
    end

    context "with no finished jobs" do
      it "returns zero" do
        jobs_scope = double("jobs_scope", empty?: true)
        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)

        result = job_monitor.average_execution_time

        expect(result).to eq(0)
      end
    end

    context "with jobs missing timestamps" do
      it "handles nil timestamps gracefully by compacting them out" do
        jobs_scope = double("jobs_scope")
        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:empty?).and_return(false)

        # Mix of valid and invalid timestamp pairs
        timestamp_data = [
          [ nil, Time.current ],                     # Invalid - nil claimed_at
          [ Time.current - 30, nil ],               # Invalid - nil finished_at
          [ Time.current - 20, Time.current - 10 ]  # Valid - 10 second execution
        ]
        allow(jobs_scope).to receive(:pluck).and_return(timestamp_data)

        result = job_monitor.average_execution_time

        # Should only use the valid execution time
        expect(result).to eq(10.0)
      end
    end

    context "with all invalid timestamps" do
      it "returns zero when no valid execution times exist" do
        jobs_scope = double("jobs_scope")
        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:empty?).and_return(false)

        # All timestamp pairs are invalid
        timestamp_data = [
          [ nil, Time.current ],
          [ Time.current - 30, nil ]
        ]
        allow(jobs_scope).to receive(:pluck).and_return(timestamp_data)

        result = job_monitor.average_execution_time

        expect(result).to eq(0)
      end
    end

    context "with precise execution time calculations" do
      it "rounds result to 2 decimal places" do
        jobs_scope = double("jobs_scope")
        allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:empty?).and_return(false)

        # Execution times that create non-round average
        timestamp_data = [
          [ Time.current - 30, Time.current - 25.333 ], # 4.667 second execution
          [ Time.current - 20, Time.current - 15.111 ]  # 4.889 second execution
        ]
        allow(jobs_scope).to receive(:pluck).and_return(timestamp_data)

        result = job_monitor.average_execution_time

        expect(result).to be_a(Float)
        expect(result.to_s.split('.').last.length).to be <= 2
      end
    end
  end

  describe ".calculate_failure_rate" do
    context "with both successful and failed jobs" do
      it "calculates failure percentage based on total jobs" do
        # 100 total jobs, 5 failed = 5% failure rate
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count).and_return(100)
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count).and_return(5)

        result = job_monitor.calculate_failure_rate

        expect(result).to eq(5.0)
      end
    end

    context "with no jobs" do
      it "returns zero to avoid division by zero" do
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count).and_return(0)
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count).and_return(0)

        result = job_monitor.calculate_failure_rate

        expect(result).to eq(0)
      end
    end

    context "with no failed jobs" do
      it "returns zero failure rate" do
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count).and_return(50)
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count).and_return(0)

        result = job_monitor.calculate_failure_rate

        expect(result).to eq(0.0)
      end
    end

    context "with all jobs failed" do
      it "returns 100% failure rate" do
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count).and_return(10)
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count).and_return(10)

        result = job_monitor.calculate_failure_rate

        expect(result).to eq(100.0)
      end
    end

    context "with precise failure rate calculations" do
      it "rounds result to 2 decimal places" do
        # 7 failed out of 33 total = 21.212121...%
        allow(@mocked_models[:job]).to receive_message_chain(:where, :count).and_return(33)
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count).and_return(7)

        result = job_monitor.calculate_failure_rate

        expect(result).to eq(21.21)
      end
    end

    context "filters jobs within time window" do
      it "uses the same time window for both total and failed jobs" do
        expect(@mocked_models[:job]).to receive(:where)
          .with(created_at: one_hour_ago..current_time)
          .and_return(@mocked_models[:job])

        expect(@mocked_models[:failed]).to receive(:where)
          .with(created_at: one_hour_ago..current_time)
          .and_return(@mocked_models[:failed])

        allow(@mocked_models[:job]).to receive(:count).and_return(100)
        allow(@mocked_models[:failed]).to receive(:count).and_return(5)

        job_monitor.calculate_failure_rate
      end
    end
  end

  context "error handling" do
    it "handles SolidQueue connection errors" do
      allow(@mocked_models[:job]).to receive(:where)
        .and_raise(ActiveRecord::ConnectionNotEstablished)

      expect {
        job_monitor.total_jobs_count
      }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    end

    it "handles missing SolidQueue tables" do
      allow(@mocked_models[:job]).to receive(:pending)
        .and_raise(ActiveRecord::StatementInvalid.new("Table 'solid_queue_jobs' doesn't exist"))

      expect {
        job_monitor.jobs_by_status
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "fails with corrupt timestamp data" do
      jobs_scope = double("jobs_scope")
      where_chain = double("where_chain")
      not_scope = double("not_scope")
      final_scope = double("final_scope")

      allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
      allow(jobs_scope).to receive(:where).and_return(where_chain)
      allow(where_chain).to receive(:where).and_return(not_scope)
      allow(not_scope).to receive(:not).with(claimed_at: nil).and_return(final_scope)
      allow(final_scope).to receive(:empty?).and_return(false)

      # Corrupt data that will cause calculation errors in the current implementation
      corrupt_data = [
        [ "not a timestamp", Time.current ],
        [ Time.current, "not a timestamp" ]
      ]
      allow(final_scope).to receive(:pluck).and_return(corrupt_data)

      expect { job_monitor.average_wait_time }.to raise_error(TypeError)
    end
  end

  context "performance considerations" do
    it "uses efficient database queries" do
      # Verify that we're using database-level aggregation
      scope_chain = double("scope_chain")
      allow(@mocked_models[:job]).to receive(:where).and_return(scope_chain)
      allow(scope_chain).to receive(:group).and_return(scope_chain)
      expect(scope_chain).to receive(:count).once.and_return({})

      job_monitor.jobs_by_class
    end

    it "filters data before aggregation for time windows" do
      expect(@mocked_models[:job]).to receive(:where).with(created_at: one_hour_ago..current_time).ordered
      expect(@mocked_models[:job]).to receive(:count).ordered

      job_monitor.total_jobs_count
    end

    it "combines multiple metrics efficiently" do
      # Mock all the sub-methods to avoid division by zero
      allow(job_monitor).to receive(:total_jobs_count).and_return(100)
      allow(job_monitor).to receive(:jobs_by_status).and_return({ pending: 10, processing: 5, finished: 80, failed: 5 })
      allow(job_monitor).to receive(:jobs_by_class).and_return({ "ProcessEmailJob" => 50 })
      allow(job_monitor).to receive(:average_wait_time).and_return(2.5)
      allow(job_monitor).to receive(:average_execution_time).and_return(15.75)
      allow(job_monitor).to receive(:calculate_failure_rate).and_return(5.0)

      result = job_monitor.metrics

      # Should successfully aggregate all metrics without errors
      expect(result).to be_a(Hash)
      expect(result.keys.size).to eq(6)
    end
  end

  context "data integrity" do
    it "handles large job counts" do
      allow(@mocked_models[:job]).to receive_message_chain(:where, :count)
        .and_return(1_000_000)

      result = job_monitor.total_jobs_count

      expect(result).to eq(1_000_000)
    end

    it "handles very long execution times" do
      jobs_scope = double("jobs_scope")
      allow(@mocked_models[:job]).to receive(:finished).and_return(jobs_scope)
      allow(jobs_scope).to receive(:where).and_return(jobs_scope)
      allow(jobs_scope).to receive(:empty?).and_return(false)

      # Very long execution time (1 hour)
      timestamp_data = [
        [ Time.current - 3600, Time.current ]
      ]
      allow(jobs_scope).to receive(:pluck).and_return(timestamp_data)

      result = job_monitor.average_execution_time

      expect(result).to eq(3600.0)
    end

    it "handles job class names with special characters" do
      job_counts = {
        "Email::ProcessorJob" => 50,
        "Sync::Worker-Job" => 25,
        "Bulk.Operations::Job" => 10
      }

      scope_chain = double("scope_chain")
      allow(@mocked_models[:job]).to receive(:where).and_return(scope_chain)
      allow(scope_chain).to receive(:group).and_return(scope_chain)
      allow(scope_chain).to receive(:count).and_return(job_counts)

      result = job_monitor.jobs_by_class

      expect(result.keys).to contain_exactly(
        "Email::ProcessorJob",
        "Sync::Worker-Job",
        "Bulk.Operations::Job"
      )
    end
  end
end
