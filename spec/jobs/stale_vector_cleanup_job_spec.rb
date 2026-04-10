# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaleVectorCleanupJob, type: :job, unit: true do
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform", unit: true do
    it "runs without error when no stale vectors exist" do
      expect { job.perform }.not_to raise_error
    end

    it "logs the count of cleaned up rows" do
      expect(Rails.logger).to receive(:info).with(/cleaned_up=0/)
      job.perform
    end

    context "with stale vectors (last_seen_at > 6 months ago)" do
      let(:category) { create(:category) }

      let!(:stale_vector) do
        create(:categorization_vector,
          merchant_normalized: "old-store",
          category: category,
          last_seen_at: 7.months.ago)
      end

      it "deletes stale vectors" do
        expect { job.perform }.to change(CategorizationVector, :count).by(-1)
      end

      it "logs the count of cleaned up rows" do
        expect(Rails.logger).to receive(:info).with(/cleaned_up=1/)
        job.perform
      end
    end

    context "with recent vectors (last_seen_at < 6 months ago)" do
      let(:category) { create(:category) }

      let!(:recent_vector) do
        create(:categorization_vector,
          merchant_normalized: "fresh-store",
          category: category,
          last_seen_at: 3.months.ago)
      end

      it "preserves recent vectors" do
        expect { job.perform }.not_to change(CategorizationVector, :count)
      end
    end

    context "with a mix of stale and recent vectors" do
      let(:category) { create(:category) }

      let!(:stale_vector) do
        create(:categorization_vector,
          merchant_normalized: "ancient-store",
          category: category,
          last_seen_at: 8.months.ago)
      end

      let!(:recent_vector) do
        create(:categorization_vector,
          merchant_normalized: "new-store",
          category: category,
          last_seen_at: 1.month.ago)
      end

      it "only deletes stale vectors" do
        expect { job.perform }.to change(CategorizationVector, :count).by(-1)
        expect(CategorizationVector.find_by(merchant_normalized: "new-store")).to be_present
      end

      it "logs the correct count" do
        expect(Rails.logger).to receive(:info).with(/cleaned_up=1/)
        job.perform
      end
    end

    context "when deletion raises an error" do
      before do
        allow(CategorizationVector).to receive(:stale).and_raise(StandardError, "DB error")
      end

      it "logs the error" do
        expect(Rails.logger).to receive(:error).with(/DB error/)
        expect { job.perform }.to raise_error(StandardError)
      end

      it "re-raises the error for ActiveJob retry" do
        expect { job.perform }.to raise_error(StandardError, "DB error")
      end
    end
  end

  describe "job configuration", unit: true do
    it "is queued on the low queue" do
      expect(described_class.queue_name).to eq("low")
    end
  end
end
