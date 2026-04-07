# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::SyncMetricsCollector, type: :service, unit: true do
  let(:sync_session) { create(:sync_session, :running) }
  let(:collector) { described_class.new(sync_session) }

  describe "#flush_buffer" do
    context "when the buffer is empty" do
      it "does nothing and returns nil" do
        expect(SyncMetric).not_to receive(:import!)
        collector.flush_buffer
      end
    end

    context "when the buffer contains valid metrics" do
      let(:valid_metric) do
        SyncMetric.new(
          sync_session: sync_session,
          metric_type: "email_fetch",
          success: true,
          duration: 123.0,
          emails_processed: 5,
          started_at: Time.current
        )
      end

      before do
        collector.instance_variable_set(:@metrics_buffer, [ valid_metric ])
      end

      it "imports metrics with validation enabled (no validate: false option)" do
        # import! is called with just the array — no options hash means validate: true by default
        expect(SyncMetric).to receive(:import!).with([ valid_metric ]).and_call_original

        collector.flush_buffer
      end

      it "clears the buffer after a successful import" do
        allow(SyncMetric).to receive(:import!).and_return(true)
        collector.flush_buffer
        expect(collector.metrics_buffer).to be_empty
      end
    end

    context "when import raises ActiveRecord::RecordInvalid" do
      let(:invalid_metric) do
        SyncMetric.new(
          sync_session: sync_session,
          metric_type: "INVALID_TYPE_NOT_IN_ENUM",
          success: true,
          started_at: Time.current
        )
      end

      before do
        collector.instance_variable_set(:@metrics_buffer, [ invalid_metric ])
      end

      it "logs the error and does not re-raise" do
        record_invalid = ActiveRecord::RecordInvalid.new(invalid_metric)
        allow(SyncMetric).to receive(:import!).and_raise(record_invalid)
        allow(Rails.logger).to receive(:error)

        expect { collector.flush_buffer }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(a_string_matching(/Failed to save metrics/))
      end

      it "clears the buffer after handling the error" do
        allow(SyncMetric).to receive(:import!).and_raise(
          ActiveRecord::RecordInvalid.new(invalid_metric)
        )
        allow(Rails.logger).to receive(:error)

        collector.flush_buffer
        expect(collector.metrics_buffer).to be_empty
      end
    end

    context "when import raises ActiveRecord::StatementInvalid" do
      before do
        metric = SyncMetric.new(
          sync_session: sync_session,
          metric_type: "email_fetch",
          success: true,
          started_at: Time.current
        )
        collector.instance_variable_set(:@metrics_buffer, [ metric ])
      end

      it "logs the error and does not re-raise" do
        allow(SyncMetric).to receive(:import!).and_raise(
          ActiveRecord::StatementInvalid.new("PG::Error: something went wrong")
        )
        allow(Rails.logger).to receive(:error)

        expect { collector.flush_buffer }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(a_string_matching(/Failed to save metrics/))
      end

      it "clears the buffer after handling the error" do
        allow(SyncMetric).to receive(:import!).and_raise(
          ActiveRecord::StatementInvalid.new("PG::Error: something went wrong")
        )
        allow(Rails.logger).to receive(:error)

        collector.flush_buffer
        expect(collector.metrics_buffer).to be_empty
      end
    end

    context "when import raises a non-ActiveRecord exception" do
      before do
        metric = SyncMetric.new(
          sync_session: sync_session,
          metric_type: "email_fetch",
          success: true,
          started_at: Time.current
        )
        collector.instance_variable_set(:@metrics_buffer, [ metric ])
      end

      it "does NOT rescue SystemStackError and lets it propagate" do
        allow(SyncMetric).to receive(:import!).and_raise(SystemStackError)

        expect { collector.flush_buffer }.to raise_error(SystemStackError)
      end

      it "does NOT rescue NoMemoryError and lets it propagate" do
        allow(SyncMetric).to receive(:import!).and_raise(NoMemoryError)

        expect { collector.flush_buffer }.to raise_error(NoMemoryError)
      end

      it "does NOT rescue RuntimeError and lets it propagate" do
        allow(SyncMetric).to receive(:import!).and_raise(RuntimeError, "unexpected failure")

        expect { collector.flush_buffer }.to raise_error(RuntimeError, "unexpected failure")
      end
    end
  end

  describe "#record_metric" do
    it "adds a metric to the buffer" do
      expect {
        collector.record_metric(metric_type: :email_fetch, success: true)
      }.to change { collector.metrics_buffer.size }.by(1)
    end

    it "auto-flushes when buffer reaches 10 metrics" do
      allow(SyncMetric).to receive(:import!).and_return(true)

      9.times do
        collector.record_metric(metric_type: :email_fetch, success: true)
      end

      expect(SyncMetric).to receive(:import!).with(anything)
      collector.record_metric(metric_type: :email_fetch, success: true)
    end

    it "auto-flushes immediately for session_overall metric type" do
      allow(SyncMetric).to receive(:import!).and_return(true)

      expect(SyncMetric).to receive(:import!).with(anything)
      collector.record_metric(metric_type: :session_overall, success: true)
    end
  end
end
