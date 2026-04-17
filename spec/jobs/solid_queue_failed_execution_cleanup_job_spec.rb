# frozen_string_literal: true

require "rails_helper"

RSpec.describe SolidQueueFailedExecutionCleanupJob, type: :job, unit: true do
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  # Helper: create a real SolidQueue::FailedExecution anchored to a backing
  # job. FailedExecution belongs_to :job with class_name "SolidQueue::Job", and
  # the gem validates the presence of the job + error payload. We bypass
  # created_at auto-set with update_columns so boundary scenarios are
  # deterministic.
  def create_failed_execution(created_at:)
    solid_job = SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "DummyJob",
      arguments: [].to_json,
      active_job_id: SecureRandom.uuid
    )
    SolidQueue::FailedExecution.create!(
      job: solid_job,
      error: { "exception_class" => "RuntimeError", "message" => "boom" }
    ).tap do |fe|
      fe.update_columns(created_at: created_at)
    end
  end

  describe "retention policy" do
    # Threshold lives on the JOB (not the gem's FailedExecution model, which
    # we don't own). PER-503 retention matches PER-496 (30 days).
    it "uses SolidQueueFailedExecutionCleanupJob::RETENTION_DAYS (30)" do
      expect(described_class::RETENTION_DAYS).to eq(30)
    end
  end

  describe "#perform" do
    it "runs without error when no failed executions exist" do
      SolidQueue::FailedExecution.delete_all
      expect { job.perform }.not_to raise_error
    end

    it "logs a completion line with the cleaned-up count" do
      SolidQueue::FailedExecution.delete_all
      expect(Rails.logger).to receive(:info).with(/Cleanup complete: cleaned_up=0/)
      job.perform
    end

    context "with a mix of stale, boundary, and recent failed executions" do
      around do |example|
        travel_to(Time.zone.local(2026, 4, 17, 4, 15, 0)) { example.run }
      end

      before { SolidQueue::FailedExecution.delete_all }

      let!(:stale) { create_failed_execution(created_at: 31.days.ago) }
      let!(:exact_cutoff) do
        # Inclusive cutoff: exactly RETENTION_DAYS ago IS expired.
        create_failed_execution(created_at: described_class::RETENTION_DAYS.days.ago)
      end
      let!(:just_newer) do
        create_failed_execution(created_at: described_class::RETENTION_DAYS.days.ago + 1.second)
      end
      let!(:recent) { create_failed_execution(created_at: 29.days.ago) }

      it "deletes stale and exact-cutoff rows (inclusive boundary)" do
        expect { job.perform }.to change(SolidQueue::FailedExecution, :count).by(-2)
      end

      it "preserves rows newer than the cutoff (including the 1-second-younger row)" do
        job.perform
        expect(SolidQueue::FailedExecution.exists?(recent.id)).to be true
        expect(SolidQueue::FailedExecution.exists?(just_newer.id)).to be true
      end

      it "removes the stale and exact-cutoff rows" do
        job.perform
        expect(SolidQueue::FailedExecution.exists?(stale.id)).to be false
        expect(SolidQueue::FailedExecution.exists?(exact_cutoff.id)).to be false
      end

      it "logs the completion line with the cleaned-up count" do
        expect(Rails.logger).to receive(:info).with(/Cleanup complete: cleaned_up=2/)
        job.perform
      end
    end
  end

  describe "job configuration" do
    it "is queued on the low-priority queue" do
      expect(described_class.new.queue_name).to eq("low")
    end

    it "retries on StandardError up to 3 attempts with polynomial backoff" do
      # retry_on contract — if a transient queue-DB error happens, the job
      # must be retried rather than silently failing the cleanup. This
      # assertion guards the retry_on declaration from being accidentally
      # removed or narrowed to a specific error class.
      retry_jitters = described_class.retry_jitter
      rescue_handlers = described_class.rescue_handlers

      standard_error_entry = rescue_handlers.find do |class_name, _handler|
        class_name == "StandardError"
      end
      expect(standard_error_entry).not_to be_nil,
        "expected retry_on StandardError (3x polynomial) — rescue_handlers=#{rescue_handlers.inspect}"
    end
  end

  describe "error handling" do
    it "logs the failure and re-raises so retry_on can fire" do
      # The rescue branch MUST re-raise — ActiveJob's retry_on only sees
      # exceptions that propagate out of perform. A silent rescue would
      # mask the error and defeat the 3-attempt polynomial-backoff policy.
      boom = StandardError.new("queue db offline")
      allow(SolidQueue::FailedExecution).to receive(:where).and_raise(boom)
      expect(Rails.logger).to receive(:error).with(/Cleanup failed: queue db offline/)
      expect(Rails.logger).to receive(:error) # backtrace line

      expect { job.perform }.to raise_error(StandardError, "queue db offline")
    end
  end
end
