# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::DashboardInsightsService, type: :service, unit: true do
  subject(:service) { described_class.new(**params) }

  let(:monthly_metrics) { { total_amount: 150_000.0, transaction_count: 25 } }
  let(:monthly_trends) { {} }
  let(:budgets) { { has_budget: true, amount: 500_000.0 } }
  let(:uncategorized_count) { 0 }
  let(:daily_average) { 5_000.0 }
  let(:category_breakdown) { [] }

  let(:params) do
    {
      monthly_metrics: monthly_metrics,
      monthly_trends: monthly_trends,
      budgets: budgets,
      uncategorized_count: uncategorized_count,
      daily_average: daily_average,
      category_breakdown: category_breakdown
    }
  end

  describe "#insights" do
    context "spending velocity warning when projected spend exceeds budget" do
      let(:monthly_metrics) { { total_amount: 300_000.0 } }
      let(:budgets) { { has_budget: true, amount: 400_000.0 } }

      it "returns a warning insight when projected spend exceeds budget" do
        # With total_amount of 300_000 spent in Date.current.day days,
        # projected = (300_000 / days_elapsed) * days_in_month
        # For most days in a month this will exceed 400_000
        travel_to Date.new(2026, 4, 15) do
          insights = service.insights
          velocity_insight = insights.find { |i| i[:type] == :spending_velocity }

          expect(velocity_insight).to be_present
          expect(velocity_insight[:severity]).to eq(:warning)
          expect(velocity_insight[:message]).to match(/Projected to exceed budget/)
          expect(velocity_insight[:icon]).to be_present
        end
      end
    end

    context "spending velocity info when on track" do
      let(:monthly_metrics) { { total_amount: 100_000.0 } }
      let(:budgets) { { has_budget: true, amount: 500_000.0 } }

      it "returns an info insight when projected spend is within budget" do
        travel_to Date.new(2026, 4, 15) do
          insights = service.insights
          velocity_insight = insights.find { |i| i[:type] == :spending_velocity }

          expect(velocity_insight).to be_present
          expect(velocity_insight[:severity]).to eq(:info)
          expect(velocity_insight[:message]).to match(/On track to stay within budget/)
        end
      end
    end

    context "uncategorized items" do
      let(:uncategorized_count) { 5 }

      it "returns an info insight when uncategorized expenses exist" do
        insights = service.insights
        uncat_insight = insights.find { |i| i[:type] == :uncategorized_items }

        expect(uncat_insight).to be_present
        expect(uncat_insight[:severity]).to eq(:info)
        expect(uncat_insight[:message]).to match(/5 expenses need categorization/)
        expect(uncat_insight[:icon]).to be_present
      end
    end

    context "no uncategorized items" do
      let(:uncategorized_count) { 0 }

      it "does not include uncategorized insight" do
        insights = service.insights
        uncat_insight = insights.find { |i| i[:type] == :uncategorized_items }

        expect(uncat_insight).to be_nil
      end
    end

    context "max 3 insights returned" do
      let(:uncategorized_count) { 3 }
      let(:monthly_metrics) { { total_amount: 300_000.0 } }
      let(:budgets) { { has_budget: true, amount: 400_000.0 } }

      it "returns at most 3 insights" do
        travel_to Date.new(2026, 4, 15) do
          insights = service.insights
          expect(insights.length).to be <= 3
        end
      end
    end

    context "insights sorted by severity" do
      let(:uncategorized_count) { 3 }
      let(:monthly_metrics) { { total_amount: 300_000.0 } }
      let(:budgets) { { has_budget: true, amount: 400_000.0 } }

      it "places warnings before info insights" do
        travel_to Date.new(2026, 4, 15) do
          insights = service.insights
          severities = insights.map { |i| i[:severity] }
          warning_indices = severities.each_index.select { |i| severities[i] == :warning }
          info_indices = severities.each_index.select { |i| severities[i] == :info }

          if warning_indices.any? && info_indices.any?
            expect(warning_indices.max).to be < info_indices.min
          end
        end
      end
    end

    context "empty array when no insights trigger" do
      let(:monthly_metrics) { { total_amount: 0.0 } }
      let(:budgets) { { has_budget: false } }
      let(:uncategorized_count) { 0 }

      it "returns an empty array" do
        insights = service.insights
        expect(insights).to eq([])
      end
    end

    context "with no budget data" do
      let(:budgets) { { has_budget: false } }
      let(:uncategorized_count) { 0 }

      it "skips budget-related insights" do
        insights = service.insights
        velocity_insight = insights.find { |i| i[:type] == :spending_velocity }
        budget_insight = insights.find { |i| i[:type] == :budget_on_track }

        expect(velocity_insight).to be_nil
        expect(budget_insight).to be_nil
      end
    end

    context "insight hash structure" do
      let(:uncategorized_count) { 2 }

      it "returns insights with the correct keys" do
        insights = service.insights
        insight = insights.first

        expect(insight).to include(:type, :severity, :icon, :message)
        expect(insight).to have_key(:link_path)
      end
    end

    context "spending velocity with zero total" do
      let(:monthly_metrics) { { total_amount: 0.0 } }
      let(:budgets) { { has_budget: true, amount: 500_000.0 } }

      it "returns budget on track insight" do
        insights = service.insights
        velocity_insight = insights.find { |i| i[:type] == :spending_velocity }

        expect(velocity_insight).to be_present
        expect(velocity_insight[:severity]).to eq(:info)
      end
    end

    context "spending velocity calculates projected amount correctly" do
      let(:monthly_metrics) { { total_amount: 200_000.0 } }
      let(:budgets) { { has_budget: true, amount: 500_000.0 } }

      it "uses correct projection formula" do
        travel_to Date.new(2026, 4, 10) do
          # days_elapsed = 10, days_in_month = 30
          # projected = (200_000 / 10) * 30 = 600_000 > 500_000 => warning
          insights = service.insights
          velocity_insight = insights.find { |i| i[:type] == :spending_velocity }

          expect(velocity_insight[:severity]).to eq(:warning)
          # Projected exceeds by 100_000
          expect(velocity_insight[:message]).to include("100,000")
        end
      end
    end
  end
end
