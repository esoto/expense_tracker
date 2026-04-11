# frozen_string_literal: true

require "rails_helper"

RSpec.describe LlmCacheCleanupJob, type: :job, unit: true do
  let(:job) { described_class.new }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "#perform" do
    it "runs without error when no expired entries exist" do
      expect { job.perform }.not_to raise_error
    end

    it "logs the count of cleaned up rows" do
      expect(Rails.logger).to receive(:info).with(/cleaned_up=0/)
      job.perform
    end

    context "with expired cache entries" do
      let(:category) { create(:category) }

      let!(:expired_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: "old-merchant",
          category: category,
          expires_at: 1.day.ago)
      end

      it "deletes expired entries" do
        expect { job.perform }.to change(LlmCategorizationCacheEntry, :count).by(-1)
      end

      it "logs the count of cleaned up rows" do
        expect(Rails.logger).to receive(:info).with(/cleaned_up=1/)
        job.perform
      end
    end

    context "with active cache entries" do
      let(:category) { create(:category) }

      let!(:active_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: "fresh-merchant",
          category: category,
          expires_at: 30.days.from_now)
      end

      it "preserves active entries" do
        expect { job.perform }.not_to change(LlmCategorizationCacheEntry, :count)
      end
    end

    context "with entries that have no expiration (nil expires_at)" do
      let(:category) { create(:category) }

      let!(:no_expiry_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: "permanent-merchant",
          category: category,
          expires_at: nil)
      end

      it "preserves entries without expiration" do
        expect { job.perform }.not_to change(LlmCategorizationCacheEntry, :count)
      end
    end

    context "with a mix of expired and active entries" do
      let(:category) { create(:category) }

      let!(:expired_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: "ancient-merchant",
          category: category,
          expires_at: 2.days.ago)
      end

      let!(:active_entry) do
        create(:llm_categorization_cache_entry,
          merchant_normalized: "new-merchant",
          category: category,
          expires_at: 60.days.from_now)
      end

      it "only deletes expired entries" do
        expect { job.perform }.to change(LlmCategorizationCacheEntry, :count).by(-1)
        expect(LlmCategorizationCacheEntry.find_by(merchant_normalized: "new-merchant")).to be_present
      end

      it "logs the correct count" do
        expect(Rails.logger).to receive(:info).with(/cleaned_up=1/)
        job.perform
      end
    end

    context "when deletion raises an error" do
      before do
        allow(LlmCategorizationCacheEntry).to receive(:expired).and_raise(StandardError, "DB error")
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

  describe "job configuration" do
    it "is queued on the low queue" do
      expect(described_class.queue_name).to eq("low")
    end
  end
end
