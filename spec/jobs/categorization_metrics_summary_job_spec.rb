# frozen_string_literal: true

require "rails_helper"

RSpec.describe CategorizationMetricsSummaryJob, :unit, type: :job do
  subject(:job) { described_class.new }

  let(:category) { create(:category) }
  let(:other_category) { create(:category) }

  def create_metric(layer:, corrected: false, confidence: 0.85, api_cost: 0.0, created_at: 2.days.ago)
    expense = create(:expense)
    traits = []
    traits << :corrected if corrected
    attrs = {
      expense: expense,
      category: category,
      layer_used: layer,
      confidence: confidence,
      api_cost: api_cost,
      created_at: created_at
    }
    if corrected
      attrs[:was_corrected] = true
      attrs[:corrected_to_category] = other_category
      attrs[:time_to_correction_hours] = 2
    end
    create(:categorization_metric, **attrs)
  end

  before do
    # Clear any ONNX trigger counters
    Rails.cache.delete("onnx_trigger:fallback_weeks")
    Rails.cache.delete("onnx_trigger:correction_weeks")
  end

  describe "#perform" do
    context "with no metrics in the past 7 days" do
      it "logs that no data was found" do
        expect(Rails.logger).to receive(:info).with(/No categorization metrics found/)
        job.perform
      end
    end

    context "with metrics from older than 7 days" do
      before do
        create_metric(layer: "pattern", created_at: 10.days.ago)
      end

      it "does not include them in the summary" do
        expect(Rails.logger).to receive(:info).with(/No categorization metrics found/)
        job.perform
      end
    end

    context "with per-layer accuracy computation" do
      before do
        # pattern layer: 8 total, 2 corrected => accuracy 75%
        6.times { create_metric(layer: "pattern") }
        2.times { create_metric(layer: "pattern", corrected: true) }

        # pg_trgm layer: 4 total, 1 corrected => accuracy 75%
        3.times { create_metric(layer: "pg_trgm") }
        1.times { create_metric(layer: "pg_trgm", corrected: true) }

        # haiku layer: 3 total, 0 corrected => accuracy 100%
        3.times { create_metric(layer: "haiku", api_cost: 0.001) }
      end

      it "computes correct per-layer accuracy" do
        expect(Rails.logger).to receive(:info).with(/pattern.*75\.0%/).at_least(:once)
        expect(Rails.logger).to receive(:info).with(/pg_trgm.*75\.0%/).at_least(:once)
        expect(Rails.logger).to receive(:info).with(/haiku.*100\.0%/).at_least(:once)
        allow(Rails.logger).to receive(:info)

        job.perform
      end

      it "computes LLM fallback rate" do
        # haiku_count = 3, total = 15 => 20%
        expect(Rails.logger).to receive(:info).with(/Fallback rate.*20\.0%/).at_least(:once)
        allow(Rails.logger).to receive(:info)

        job.perform
      end

      it "computes user correction rate" do
        # corrections = 3, total = 15 => 20%
        expect(Rails.logger).to receive(:info).with(/Correction rate.*20\.0%/).at_least(:once)
        allow(Rails.logger).to receive(:info)

        job.perform
      end

      it "computes total API spend" do
        # 3 haiku metrics * 0.001 = 0.003
        expect(Rails.logger).to receive(:info).with(/API spend.*0\.003/).at_least(:once)
        allow(Rails.logger).to receive(:info)

        job.perform
      end

      it "computes average confidence per layer" do
        expect(Rails.logger).to receive(:info).with(/pattern.*avg_confidence/).at_least(:once)
        allow(Rails.logger).to receive(:info)

        job.perform
      end
    end

    it "logs summary at info level" do
      create_metric(layer: "pattern")

      allow(Rails.logger).to receive(:info)
      job.perform

      expect(Rails.logger).to have_received(:info).at_least(:once)
    end
  end

  describe "ONNX trigger warnings" do
    context "when fallback rate exceeds 15%" do
      before do
        # 5 haiku out of 10 total => 50% fallback rate
        5.times { create_metric(layer: "haiku", api_cost: 0.001) }
        5.times { create_metric(layer: "pattern") }
      end

      it "increments the fallback weeks counter" do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)

        job.perform

        expect(Rails.cache.read("onnx_trigger:fallback_weeks")).to eq(1)
      end
    end

    context "when correction rate exceeds 10%" do
      before do
        # 3 corrected out of 10 total => 30% correction rate
        7.times { create_metric(layer: "pattern") }
        3.times { create_metric(layer: "pattern", corrected: true) }
      end

      it "increments the correction weeks counter" do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)

        job.perform

        expect(Rails.cache.read("onnx_trigger:correction_weeks")).to eq(1)
      end
    end

    context "when metrics return to healthy range" do
      before do
        Rails.cache.write("onnx_trigger:fallback_weeks", 2, expires_in: 90.days)
        Rails.cache.write("onnx_trigger:correction_weeks", 2, expires_in: 90.days)

        # All pattern, no corrections => healthy
        10.times { create_metric(layer: "pattern") }
      end

      it "resets fallback counter to zero" do
        allow(Rails.logger).to receive(:info)

        job.perform

        expect(Rails.cache.read("onnx_trigger:fallback_weeks")).to eq(0)
      end

      it "resets correction counter to zero" do
        allow(Rails.logger).to receive(:info)

        job.perform

        expect(Rails.cache.read("onnx_trigger:correction_weeks")).to eq(0)
      end
    end

    context "when fallback counter reaches 3 consecutive weeks" do
      before do
        Rails.cache.write("onnx_trigger:fallback_weeks", 2, expires_in: 90.days)

        # High fallback rate to trigger increment to 3
        8.times { create_metric(layer: "haiku", api_cost: 0.001) }
        2.times { create_metric(layer: "pattern") }
      end

      it "logs a warning about sustained high fallback rate" do
        allow(Rails.logger).to receive(:info)

        expect(Rails.logger).to receive(:warn).with(/ONNX.*fallback rate.*3 consecutive weeks/)

        job.perform
      end
    end

    context "when correction counter reaches 3 consecutive weeks" do
      before do
        Rails.cache.write("onnx_trigger:correction_weeks", 2, expires_in: 90.days)

        # High correction rate to trigger increment to 3
        5.times { create_metric(layer: "pattern") }
        5.times { create_metric(layer: "pattern", corrected: true) }
      end

      it "logs a warning about sustained high correction rate" do
        allow(Rails.logger).to receive(:info)

        expect(Rails.logger).to receive(:warn).with(/ONNX.*correction rate.*3 consecutive weeks/)

        job.perform
      end
    end

    context "when both counters reach 12 consecutive weeks" do
      before do
        Rails.cache.write("onnx_trigger:fallback_weeks", 11, expires_in: 90.days)
        Rails.cache.write("onnx_trigger:correction_weeks", 11, expires_in: 90.days)

        # Both high fallback and high correction
        5.times { create_metric(layer: "haiku", api_cost: 0.001) }
        3.times { create_metric(layer: "pattern") }
        2.times { create_metric(layer: "pattern", corrected: true) }
      end

      it "logs a strong recommendation to evaluate ONNX" do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)

        job.perform

        expect(Rails.logger).to have_received(:warn).with(/STRONG RECOMMENDATION.*12 weeks.*ONNX/)
      end
    end
  end

  describe "job configuration" do
    it "is enqueued in the low queue" do
      expect(described_class.new.queue_name).to eq("low")
    end

    it "inherits from ApplicationJob" do
      expect(described_class.superclass).to eq(ApplicationJob)
    end
  end
end
