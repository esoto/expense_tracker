# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Monitoring::MetricsDashboardService, type: :service, unit: true do
  subject(:service) { described_class.new }

  describe "#overview" do
    context "with no metrics" do
      it "returns zeros without division errors" do
        result = service.overview(period: 30.days)

        expect(result).to eq(
          accuracy: 0.0,
          fallback_rate: 0.0,
          correction_rate: 0.0,
          api_spend: 0.0
        )
      end
    end

    context "with metrics in period" do
      before do
        # 3 uncorrected (accurate) + 1 corrected = 4 total
        create_list(:categorization_metric, 3, created_at: 5.days.ago)
        create(:categorization_metric, :corrected, created_at: 5.days.ago)

        # 2 haiku layer metrics (one already counted above as corrected)
        create(:categorization_metric, :haiku_layer, created_at: 5.days.ago)

        # Outside period - should be excluded
        create(:categorization_metric, created_at: 60.days.ago)
      end

      it "calculates accuracy as uncorrected / total * 100" do
        result = service.overview(period: 30.days)

        # 5 total in period, 4 uncorrected => 80%
        expect(result[:accuracy]).to eq(80.0)
      end

      it "calculates fallback_rate as haiku layer / total * 100" do
        result = service.overview(period: 30.days)

        # 5 total in period, 1 haiku layer => 20%
        expect(result[:fallback_rate]).to eq(20.0)
      end

      it "calculates correction_rate as corrected / total * 100" do
        result = service.overview(period: 30.days)

        # 5 total in period, 1 corrected => 20%
        expect(result[:correction_rate]).to eq(20.0)
      end

      it "sums api_cost for the period" do
        result = service.overview(period: 30.days)

        # Only the haiku layer metric has api_cost of 0.001
        expect(result[:api_spend]).to eq(0.001)
      end
    end

    context "with custom period" do
      before do
        create(:categorization_metric, created_at: 5.days.ago)
        create(:categorization_metric, created_at: 15.days.ago)
      end

      it "respects the period parameter" do
        result = service.overview(period: 10.days)

        expect(result[:accuracy]).to eq(100.0)
      end
    end
  end

  describe "#layer_performance" do
    context "with no metrics" do
      it "returns an empty array" do
        result = service.layer_performance(period: 30.days)

        expect(result).to eq([])
      end
    end

    context "with metrics across layers" do
      before do
        # Pattern layer: 2 correct, 1 corrected
        create_list(:categorization_metric, 2, layer_used: "pattern",
          confidence: 0.9, processing_time_ms: 10.0, created_at: 5.days.ago)
        create(:categorization_metric, :corrected, layer_used: "pattern",
          confidence: 0.6, processing_time_ms: 20.0, created_at: 5.days.ago)

        # Haiku layer: 1 correct
        create(:categorization_metric, :haiku_layer,
          confidence: 0.75, processing_time_ms: 150.0, created_at: 5.days.ago)

        # Outside period
        create(:categorization_metric, layer_used: "pattern", created_at: 60.days.ago)
      end

      it "returns one entry per layer" do
        result = service.layer_performance(period: 30.days)

        layers = result.map { |r| r[:layer] }
        expect(layers).to contain_exactly("pattern", "haiku")
      end

      it "calculates correct counts per layer" do
        result = service.layer_performance(period: 30.days)
        pattern_row = result.find { |r| r[:layer] == "pattern" }

        expect(pattern_row[:total]).to eq(3)
        expect(pattern_row[:correct]).to eq(2)
        expect(pattern_row[:corrected]).to eq(1)
      end

      it "calculates accuracy per layer" do
        result = service.layer_performance(period: 30.days)
        pattern_row = result.find { |r| r[:layer] == "pattern" }

        # 2 correct out of 3 total => 66.67%
        expect(pattern_row[:accuracy]).to eq(66.67)
      end

      it "calculates average confidence per layer" do
        result = service.layer_performance(period: 30.days)
        pattern_row = result.find { |r| r[:layer] == "pattern" }

        # (0.9 + 0.9 + 0.6) / 3 = 0.8
        expect(pattern_row[:avg_confidence]).to eq(0.8)
      end

      it "calculates average processing time per layer" do
        result = service.layer_performance(period: 30.days)
        pattern_row = result.find { |r| r[:layer] == "pattern" }

        # (10.0 + 10.0 + 20.0) / 3 ≈ 13.33
        expect(pattern_row[:avg_time]).to eq(13.33)
      end

      it "handles haiku layer correctly" do
        result = service.layer_performance(period: 30.days)
        haiku_row = result.find { |r| r[:layer] == "haiku" }

        expect(haiku_row[:total]).to eq(1)
        expect(haiku_row[:correct]).to eq(1)
        expect(haiku_row[:corrected]).to eq(0)
        expect(haiku_row[:accuracy]).to eq(100.0)
        expect(haiku_row[:avg_confidence]).to eq(0.75)
        expect(haiku_row[:avg_time]).to eq(150.0)
      end
    end
  end
end
