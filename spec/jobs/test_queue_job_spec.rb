# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestQueueJob, type: :job, unit: true do
  describe "job configuration" do
    it "can be instantiated" do
      expect { described_class.new }.not_to raise_error
    end

    it "is queued in the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end

  describe "#perform" do
    let(:job) { described_class.new }
    let(:logger) { instance_double(Logger) }

    before do
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(job).to receive(:sleep)
    end

    context "with default message" do
      it "executes successfully with default message" do
        expect { job.perform }.not_to raise_error
      end

      it "logs the default execution message" do
        expect(logger).to receive(:info).with("TestQueueJob: Test job executed")
        expect(logger).to receive(:info).with("TestQueueJob: Completed")

        job.perform
      end
    end

    context "with custom message" do
      let(:custom_message) { "Custom test message" }

      it "executes successfully with custom message" do
        expect { job.perform(custom_message) }.not_to raise_error
      end

      it "logs the custom execution message" do
        expect(logger).to receive(:info).with("TestQueueJob: #{custom_message}")
        expect(logger).to receive(:info).with("TestQueueJob: Completed")

        job.perform(custom_message)
      end
    end

    describe "work simulation" do
      it "includes sleep to simulate work" do
        expect(job).to receive(:sleep).with(2)

        job.perform
      end
    end
  end

  describe "ActiveJob integration" do
    it "can be enqueued" do
      expect {
        described_class.perform_later("Test message")
      }.to have_enqueued_job(described_class)
        .with("Test message")
        .on_queue("default")
    end

    it "can be enqueued without arguments" do
      expect {
        described_class.perform_later
      }.to have_enqueued_job(described_class)
        .with(no_args)
        .on_queue("default")
    end
  end
end
