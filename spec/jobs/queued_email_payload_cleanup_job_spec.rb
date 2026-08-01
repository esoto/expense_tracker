# frozen_string_literal: true

require "rails_helper"

RSpec.describe QueuedEmailPayloadCleanupJob, type: :job, unit: true do
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "retention policy" do
    it "purges processed rows after QueuedEmailPayload::PROCESSED_RETENTION (7 days)" do
      expect(QueuedEmailPayload::PROCESSED_RETENTION).to eq(7.days)
    end

    it "purges unprocessed rows after QueuedEmailPayload::UNPROCESSED_RETENTION (30 days)" do
      expect(QueuedEmailPayload::UNPROCESSED_RETENTION).to eq(30.days)
    end
  end

  describe "#perform" do
    it "runs without error when no payloads exist" do
      expect { job.perform }.not_to raise_error
    end

    it "logs a completion line with both counts" do
      expect(Rails.logger).to receive(:info).with(/processed_cleaned_up=0, unprocessed_cleaned_up=0/)
      job.perform
    end

    context "with a mix of processed and unprocessed payloads at various ages" do
      around do |example|
        travel_to(Time.zone.local(2026, 8, 1, 4, 30, 0)) { example.run }
      end

      let!(:stale_processed) do
        create(:queued_email_payload, :processed).tap do |p|
          p.update_columns(processed_at: 8.days.ago)
        end
      end

      let!(:recent_processed) do
        create(:queued_email_payload, :processed).tap do |p|
          p.update_columns(processed_at: 6.days.ago)
        end
      end

      let!(:stale_unprocessed) do
        create(:queued_email_payload).tap do |p|
          p.update_columns(created_at: 31.days.ago)
        end
      end

      let!(:recent_unprocessed) do
        create(:queued_email_payload).tap do |p|
          p.update_columns(created_at: 29.days.ago)
        end
      end

      it "deletes only the stale processed row" do
        job.perform
        expect(QueuedEmailPayload.exists?(stale_processed.id)).to be false
        expect(QueuedEmailPayload.exists?(recent_processed.id)).to be true
      end

      it "deletes only the stale unprocessed row" do
        job.perform
        expect(QueuedEmailPayload.exists?(stale_unprocessed.id)).to be false
        expect(QueuedEmailPayload.exists?(recent_unprocessed.id)).to be true
      end

      it "judges a processed row only against PROCESSED_RETENTION, ignoring created_at" do
        # created_at is old enough to be past UNPROCESSED_RETENTION, but that
        # window only applies to unprocessed rows — this row is processed, so
        # only PROCESSED_RETENTION (measured from processed_at) applies.
        recent_processed.update_columns(processed_at: 6.days.ago, created_at: 40.days.ago)

        job.perform

        expect(QueuedEmailPayload.exists?(recent_processed.id)).to be true
      end

      it "changes the total count by exactly -2" do
        expect { job.perform }.to change(QueuedEmailPayload, :count).by(-2)
      end

      it "logs the completion line with the correct counts" do
        expect(Rails.logger).to receive(:info).with(/processed_cleaned_up=1, unprocessed_cleaned_up=1/)
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
