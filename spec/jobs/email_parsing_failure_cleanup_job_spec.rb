# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailParsingFailureCleanupJob, type: :job, unit: true do
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "retention policy" do
    # The retention threshold lives on the model (PER-496 review feedback —
    # matches the LlmCategorizationCacheEntry.expired convention).
    it "uses EmailParsingFailure::RETENTION_DAYS (currently 30)" do
      expect(EmailParsingFailure::RETENTION_DAYS).to eq(30)
    end
  end

  describe "#perform" do
    it "runs without error when no failures exist" do
      expect { job.perform }.not_to raise_error
    end

    it "logs a completion line with the cleaned-up count" do
      expect(Rails.logger).to receive(:info).with(/Cleanup complete: cleaned_up=0/)
      job.perform
    end

    context "with a mix of stale, boundary, and recent failures" do
      # travel_to freezes `Time.current` so the job's `.expired` scope
      # evaluates the cutoff to the same instant our fixtures are anchored
      # against — no race between spec and job clock reads.
      around do |example|
        travel_to(Time.zone.local(2026, 4, 17, 4, 0, 0)) { example.run }
      end

      let!(:stale_failure) do
        create(:email_parsing_failure).tap do |f|
          f.update_columns(created_at: 31.days.ago)
        end
      end

      let!(:exact_cutoff_failure) do
        create(:email_parsing_failure).tap do |f|
          # Exactly at cutoff — `.expired` uses an inclusive range so this
          # row IS expired.
          f.update_columns(created_at: EmailParsingFailure::RETENTION_DAYS.days.ago)
        end
      end

      let!(:just_before_cutoff_failure) do
        create(:email_parsing_failure).tap do |f|
          f.update_columns(created_at: (EmailParsingFailure::RETENTION_DAYS.days.ago + 1.second))
        end
      end

      let!(:recent_failure) do
        create(:email_parsing_failure).tap do |f|
          f.update_columns(created_at: 29.days.ago)
        end
      end

      it "deletes rows older than or equal to the cutoff" do
        expect { job.perform }.to change(EmailParsingFailure, :count).by(-2)
      end

      it "preserves rows newer than the cutoff (including the row 1 second younger)" do
        job.perform
        expect(EmailParsingFailure.exists?(recent_failure.id)).to be true
        expect(EmailParsingFailure.exists?(just_before_cutoff_failure.id)).to be true
      end

      it "deletes the stale and exact-cutoff rows (inclusive boundary)" do
        job.perform
        expect(EmailParsingFailure.exists?(stale_failure.id)).to be false
        expect(EmailParsingFailure.exists?(exact_cutoff_failure.id)).to be false
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
