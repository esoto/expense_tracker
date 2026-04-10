# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Learning::CorrectionHandler, type: :service, unit: true do
  let(:old_category) { create(:category, name: "Groceries") }
  let(:new_category) { create(:category, name: "Restaurants") }
  let(:expense) { create(:expense, merchant_name: "Walmart Escazú", category: old_category) }
  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, error: nil, warn: nil) }
  let(:handler) { described_class.new(logger: logger) }

  describe "#handle_correction" do
    context "basic correction flow" do
      it "calls VectorUpdater.record_correction with correct params" do
        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(result[:old_vector]).to be_nil # no pre-existing vector for old category
        expect(result[:new_vector]).to be_a(CategorizationVector)
        expect(result[:new_vector].category).to eq(new_category)
      end

      it "calls MetricsRecorder.record_correction" do
        # Create a metric so MetricsRecorder has something to update
        create(:categorization_metric, expense: expense, category: old_category)

        handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        metric = CategorizationMetric.where(expense: expense).order(created_at: :desc).first
        expect(metric.was_corrected).to be true
        expect(metric.corrected_to_category).to eq(new_category)
      end

      it "returns three_strike_triggered as false when under threshold" do
        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(result[:three_strike_triggered]).to be false
      end
    end

    context "three-strike logic" do
      let(:normalized_merchant) { Services::Categorization::MerchantNormalizer.normalize("Walmart Escazú") }

      before do
        # Create a pre-existing vector for the old category with correction_count already at 2
        # (the handler will increment it to 3 via VectorUpdater, triggering three-strike)
        create(
          :categorization_vector,
          merchant_normalized: normalized_merchant,
          category: old_category,
          correction_count: 2,
          confidence: 0.7,
          last_seen_at: Time.current
        )
      end

      it "triggers three-strike when correction_count reaches threshold" do
        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(result[:three_strike_triggered]).to be true
      end

      it "drops confidence to 0.1 on the old vector" do
        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(result[:old_vector].reload.confidence).to eq(0.1)
      end

      it "deletes LLM cache entry for the merchant" do
        create(
          :llm_categorization_cache_entry,
          merchant_normalized: normalized_merchant,
          category: old_category
        )

        expect {
          handler.handle_correction(
            expense: expense,
            old_category: old_category,
            new_category: new_category
          )
        }.to change(LlmCategorizationCacheEntry, :count).by(-1)
      end

      it "logs the three-strike event" do
        handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(logger).to have_received(:info).with(/Three-strike triggered for merchant=#{normalized_merchant}/)
      end
    end

    context "three-strike with old corrections outside 30-day window" do
      let(:normalized_merchant) { Services::Categorization::MerchantNormalizer.normalize("Walmart Escazú") }

      it "does not trigger when vector was last updated outside window" do
        # correction_count is high but last_seen_at is old
        create(
          :categorization_vector,
          merchant_normalized: normalized_merchant,
          category: old_category,
          correction_count: 5,
          confidence: 0.7,
          last_seen_at: 60.days.ago
        )

        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        # After the correction, the vector's last_seen_at gets updated by the increment!
        # and correction_count goes to 6 — but the three-strike check looks at
        # the correction_count threshold AND recent activity (last 30 days).
        # Since the vector was stale before the correction, the count resets context.
        # However, the spec requirement says "correction_count >= 3 within the last 30 days"
        # The simplest interpretation: check correction_count >= 3 AND last_seen_at within 30 days
        # After increment!, last_seen_at is NOT updated by increment! — only correction_count changes
        expect(result[:three_strike_triggered]).to be false
      end
    end

    context "when LLM cache does not exist for merchant" do
      let(:normalized_merchant) { Services::Categorization::MerchantNormalizer.normalize("Walmart Escazú") }

      before do
        create(
          :categorization_vector,
          merchant_normalized: normalized_merchant,
          category: old_category,
          correction_count: 2,
          confidence: 0.7,
          last_seen_at: Time.current
        )
      end

      it "does not raise when deleting non-existent cache" do
        expect {
          handler.handle_correction(
            expense: expense,
            old_category: old_category,
            new_category: new_category
          )
        }.not_to raise_error
      end
    end

    context "when merchant has no existing vector" do
      it "handles missing old vector gracefully" do
        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(result[:old_vector]).to be_nil
        expect(result[:new_vector]).to be_a(CategorizationVector)
        expect(result[:three_strike_triggered]).to be false
      end
    end

    context "when expense has blank merchant_name" do
      let(:expense) { create(:expense, merchant_name: "", category: old_category) }

      it "handles blank merchant gracefully" do
        result = handler.handle_correction(
          expense: expense,
          old_category: old_category,
          new_category: new_category
        )

        expect(result[:three_strike_triggered]).to be false
      end
    end
  end
end
