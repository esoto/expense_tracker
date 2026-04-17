# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmailParsingFailureCleanupJob, type: :job, unit: true do
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "constants" do
    it "defines RETENTION_DAYS as 30" do
      expect(described_class::RETENTION_DAYS).to eq(30)
    end
  end

  describe "#perform" do
    it "runs without error when no failures exist" do
      expect { job.perform }.not_to raise_error
    end

    it "logs the count of cleaned up rows" do
      expect(Rails.logger).to receive(:info).with(/cleaned_up=0/)
      job.perform
    end

    context "with a mix of stale and recent failures" do
      let!(:stale_failure) do
        create(:email_parsing_failure).tap do |f|
          f.update_columns(created_at: 31.days.ago)
        end
      end

      let!(:boundary_failure) do
        create(:email_parsing_failure).tap do |f|
          # 30 days 1 second ago — should be purged (older than the cutoff)
          f.update_columns(created_at: 30.days.ago - 1.second)
        end
      end

      let!(:recent_failure) do
        create(:email_parsing_failure).tap do |f|
          f.update_columns(created_at: 29.days.ago)
        end
      end

      it "deletes rows older than 30 days" do
        expect { job.perform }.to change(EmailParsingFailure, :count).by(-2)
      end

      it "preserves rows newer than 30 days" do
        job.perform
        expect(EmailParsingFailure.exists?(recent_failure.id)).to be true
      end

      it "deletes the stale and boundary rows" do
        job.perform
        expect(EmailParsingFailure.exists?(stale_failure.id)).to be false
        expect(EmailParsingFailure.exists?(boundary_failure.id)).to be false
      end

      it "logs the count of cleaned up rows" do
        expect(Rails.logger).to receive(:info).with(/cleaned_up=2/)
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
