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
  end
end
