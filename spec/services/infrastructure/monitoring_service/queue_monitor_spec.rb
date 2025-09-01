# frozen_string_literal: true

require "rails_helper"
require_relative "../../../support/monitoring_service_test_helper"

RSpec.describe Infrastructure::MonitoringService::QueueMonitor, type: :service, unit: true do
  include MonitoringServiceTestHelper

  let(:queue_monitor) { described_class }

  before do
    setup_time_helpers
    @mocked_models = mock_solid_queue_models
  end

  describe ".metrics" do
    it "returns complete metrics structure" do
      result = queue_monitor.metrics

      expect_metric_structure(result, [
        :queue_sizes,
        :processing_times,
        :failed_jobs,
        :scheduled_jobs,
        :workers
      ])
    end

    it "aggregates all queue monitoring data" do
      # Setup specific expectations
      allow(@mocked_models[:job]).to receive(:count).and_return({ "default" => 5, "urgent" => 2 })
      allow(@mocked_models[:failed]).to receive(:count).and_return(3)
      allow(@mocked_models[:scheduled]).to receive(:count).and_return(7)

      result = queue_monitor.metrics

      expect(result[:queue_sizes]).to eq({ "default" => 5, "urgent" => 2 })
      expect(result[:failed_jobs]).to eq(3)
      expect(result[:scheduled_jobs]).to eq(7)
    end
  end

  describe ".queue_sizes" do
    context "with pending jobs in multiple queues" do
      it "returns job counts grouped by queue name" do
        queue_counts = { "default" => 10, "urgent" => 5, "low" => 3 }
        
        allow(@mocked_models[:job]).to receive_message_chain(:pending, :group, :count)
          .and_return(queue_counts)

        result = queue_monitor.queue_sizes

        expect(result).to eq(queue_counts)
        expect(result.keys).to contain_exactly("default", "urgent", "low")
      end
    end

    context "with no pending jobs" do
      it "returns empty hash" do
        allow(@mocked_models[:job]).to receive_message_chain(:pending, :group, :count)
          .and_return({})

        result = queue_monitor.queue_sizes

        expect(result).to eq({})
      end
    end

    context "with single queue" do
      it "returns single queue count" do
        allow(@mocked_models[:job]).to receive_message_chain(:pending, :group, :count)
          .and_return({ "default" => 25 })

        result = queue_monitor.queue_sizes

        expect(result).to eq({ "default" => 25 })
      end
    end
  end

  describe ".processing_times" do
    context "with finished jobs" do
      it "calculates average processing time per queue" do
        processing_times = {
          "default" => 5.25,
          "urgent" => 2.10,
          "low" => 8.75
        }

        finished_jobs = @mocked_models[:job]
        allow(finished_jobs).to receive_message_chain(
          :finished,
          :where,
          :group,
          :average
        ).and_return(processing_times)

        result = queue_monitor.processing_times

        expect(result).to eq({
          "default" => 5.25,
          "urgent" => 2.10,
          "low" => 8.75
        })
      end

      it "rounds processing times to 2 decimal places" do
        allow(@mocked_models[:job]).to receive_message_chain(
          :finished,
          :where,
          :group,
          :average
        ).and_return({ "default" => 5.123456789 })

        result = queue_monitor.processing_times

        expect(result["default"]).to eq(5.12)
      end

      it "filters jobs within the last hour" do
        expect(@mocked_models[:job]).to receive(:finished).and_return(@mocked_models[:job])
        expect(@mocked_models[:job]).to receive(:where)
          .with(finished_at: one_hour_ago..current_time)
          .and_return(@mocked_models[:job])
        
        allow(@mocked_models[:job]).to receive_message_chain(:group, :average).and_return({})

        queue_monitor.processing_times
      end
    end

    context "with no finished jobs" do
      it "returns empty hash" do
        allow(@mocked_models[:job]).to receive_message_chain(
          :finished,
          :where,
          :group,
          :average
        ).and_return({})

        result = queue_monitor.processing_times

        expect(result).to eq({})
      end
    end

    context "with PostgreSQL-specific SQL" do
      it "uses EXTRACT(EPOCH FROM ...) for time calculation" do
        expect(@mocked_models[:job]).to receive_message_chain(:finished, :where, :group)
          .and_return(@mocked_models[:job])
        
        expect(@mocked_models[:job]).to receive(:average)
          .with("EXTRACT(EPOCH FROM (finished_at - created_at))")
          .and_return({ "default" => 5.5 })

        result = queue_monitor.processing_times

        expect(result).to eq({ "default" => 5.5 })
      end
    end
  end

  describe ".failed_jobs_count" do
    context "with failed jobs" do
      it "counts failed executions in the last hour" do
        expect(@mocked_models[:failed]).to receive(:where)
          .with(created_at: one_hour_ago..current_time)
          .and_return(@mocked_models[:failed])
        
        allow(@mocked_models[:failed]).to receive(:count).and_return(15)

        result = queue_monitor.failed_jobs_count

        expect(result).to eq(15)
      end
    end

    context "with no failed jobs" do
      it "returns zero" do
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count)
          .and_return(0)

        result = queue_monitor.failed_jobs_count

        expect(result).to eq(0)
      end
    end

    context "with multiple failures" do
      it "returns accurate count" do
        allow(@mocked_models[:failed]).to receive_message_chain(:where, :count)
          .and_return(42)

        result = queue_monitor.failed_jobs_count

        expect(result).to eq(42)
      end
    end
  end

  describe ".scheduled_jobs_count" do
    context "with scheduled jobs" do
      it "counts jobs scheduled for the next hour" do
        expect(@mocked_models[:scheduled]).to receive(:where)
          .with(scheduled_at: current_time..(current_time + 1.hour))
          .and_return(@mocked_models[:scheduled])
        
        allow(@mocked_models[:scheduled]).to receive(:count).and_return(8)

        result = queue_monitor.scheduled_jobs_count

        expect(result).to eq(8)
      end
    end

    context "with no scheduled jobs" do
      it "returns zero" do
        allow(@mocked_models[:scheduled]).to receive_message_chain(:where, :count)
          .and_return(0)

        result = queue_monitor.scheduled_jobs_count

        expect(result).to eq(0)
      end
    end

    context "with many scheduled jobs" do
      it "returns accurate count" do
        allow(@mocked_models[:scheduled]).to receive_message_chain(:where, :count)
          .and_return(100)

        result = queue_monitor.scheduled_jobs_count

        expect(result).to eq(100)
      end
    end
  end

  describe ".worker_status" do
    context "with active workers" do
      it "returns counts for all process types" do
        # Setup worker counts
        worker_scope = double("worker_scope")
        allow(worker_scope).to receive(:count).and_return(5)
        
        dispatcher_scope = double("dispatcher_scope")
        allow(dispatcher_scope).to receive(:count).and_return(2)
        
        supervisor_scope = double("supervisor_scope")
        allow(supervisor_scope).to receive(:count).and_return(1)

        allow(@mocked_models[:process]).to receive(:where)
          .with(kind: "Worker").and_return(worker_scope)
        allow(@mocked_models[:process]).to receive(:where)
          .with(kind: "Dispatcher").and_return(dispatcher_scope)
        allow(@mocked_models[:process]).to receive(:where)
          .with(kind: "Supervisor").and_return(supervisor_scope)

        result = queue_monitor.worker_status

        expect(result).to eq({
          active: 5,
          dispatchers: 2,
          supervisors: 1
        })
      end
    end

    context "with no active processes" do
      it "returns zeros for all process types" do
        allow(@mocked_models[:process]).to receive(:where).and_return(@mocked_models[:process])
        allow(@mocked_models[:process]).to receive(:count).and_return(0)

        result = queue_monitor.worker_status

        expect(result).to eq({
          active: 0,
          dispatchers: 0,
          supervisors: 0
        })
      end
    end

    context "with mixed process states" do
      it "accurately counts each type" do
        worker_scope = double("worker_scope", count: 10)
        dispatcher_scope = double("dispatcher_scope", count: 3)
        supervisor_scope = double("supervisor_scope", count: 2)

        allow(@mocked_models[:process]).to receive(:where)
          .with(kind: "Worker").and_return(worker_scope)
        allow(@mocked_models[:process]).to receive(:where)
          .with(kind: "Dispatcher").and_return(dispatcher_scope)
        allow(@mocked_models[:process]).to receive(:where)
          .with(kind: "Supervisor").and_return(supervisor_scope)

        result = queue_monitor.worker_status

        expect(result[:active]).to eq(10)
        expect(result[:dispatchers]).to eq(3)
        expect(result[:supervisors]).to eq(2)
      end
    end
  end

  context "error handling" do
    it "handles SolidQueue connection errors" do
      allow(@mocked_models[:job]).to receive(:pending)
        .and_raise(ActiveRecord::ConnectionNotEstablished)

      expect {
        queue_monitor.queue_sizes
      }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    end

    it "handles missing SolidQueue tables" do
      allow(@mocked_models[:job]).to receive(:finished)
        .and_raise(ActiveRecord::StatementInvalid.new("Table 'solid_queue_jobs' doesn't exist"))

      expect {
        queue_monitor.processing_times
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "handles nil values in processing time calculation" do
      allow(@mocked_models[:job]).to receive_message_chain(
        :finished,
        :where,
        :group,
        :average
      ).and_return({ "default" => nil })

      result = queue_monitor.processing_times

      expect(result["default"]).to eq(0.0)
    end
  end

  context "performance considerations" do
    it "uses efficient database queries" do
      # Verify that we're using group and aggregate functions
      expect(@mocked_models[:job]).to receive_message_chain(:pending, :group)
        .and_return(@mocked_models[:job])
      expect(@mocked_models[:job]).to receive(:count).once

      queue_monitor.queue_sizes
    end

    it "filters data before aggregation" do
      # Verify that where clauses are applied before expensive operations
      expect(@mocked_models[:job]).to receive(:finished).ordered.and_return(@mocked_models[:job])
      expect(@mocked_models[:job]).to receive(:where).ordered.and_return(@mocked_models[:job])
      expect(@mocked_models[:job]).to receive(:group).ordered.and_return(@mocked_models[:job])
      expect(@mocked_models[:job]).to receive(:average).ordered.and_return({})

      queue_monitor.processing_times
    end

    it "combines multiple metrics efficiently" do
      call_count = 0
      
      # Track database calls
      allow(@mocked_models[:job]).to receive(:pending) do
        call_count += 1
        @mocked_models[:job]
      end

      # Call metrics which internally calls multiple methods
      queue_monitor.metrics

      # Should reuse connections efficiently
      expect(call_count).to be <= 2
    end
  end

  context "data integrity" do
    it "handles large queue sizes" do
      allow(@mocked_models[:job]).to receive_message_chain(:pending, :group, :count)
        .and_return({ "default" => 1_000_000 })

      result = queue_monitor.queue_sizes

      expect(result["default"]).to eq(1_000_000)
    end

    it "handles very long processing times" do
      allow(@mocked_models[:job]).to receive_message_chain(
        :finished,
        :where,
        :group,
        :average
      ).and_return({ "slow_queue" => 3600.50 }) # 1 hour

      result = queue_monitor.processing_times

      expect(result["slow_queue"]).to eq(3600.50)
    end

    it "handles queue names with special characters" do
      allow(@mocked_models[:job]).to receive_message_chain(:pending, :group, :count)
        .and_return({
          "email-processor" => 5,
          "sync_worker" => 3,
          "bulk.operations" => 2
        })

      result = queue_monitor.queue_sizes

      expect(result.keys).to contain_exactly("email-processor", "sync_worker", "bulk.operations")
    end
  end
end