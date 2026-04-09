require "rails_helper"

RSpec.describe SyncPerformanceHelper, type: :helper, unit: true do
  describe "#period_label", unit: true do
    it "returns Spanish label for last_hour" do
      expect(helper.period_label("last_hour")).to eq("Última hora")
    end

    it "returns Spanish label for last_24_hours" do
      expect(helper.period_label("last_24_hours")).to eq("Últimas 24 horas")
    end

    it "returns Spanish label for last_7_days" do
      expect(helper.period_label("last_7_days")).to eq("Últimos 7 días")
    end

    it "returns Spanish label for last_30_days" do
      expect(helper.period_label("last_30_days")).to eq("Últimos 30 días")
    end

    it "returns default label for unknown periods" do
      expect(helper.period_label("unknown_period")).to eq("Personalizado")
    end

    it "returns default label for nil period" do
      expect(helper.period_label(nil)).to eq("Personalizado")
    end

    it "returns default label for empty string" do
      expect(helper.period_label("")).to eq("Personalizado")
    end
  end

  describe "#success_rate_color", unit: true do
    it "returns slate for nil rate" do
      expect(helper.success_rate_color(nil)).to eq("text-slate-400")
    end

    it "returns emerald for excellent rates (95-100)" do
      expect(helper.success_rate_color(95)).to eq("text-emerald-600")
      expect(helper.success_rate_color(98)).to eq("text-emerald-600")
      expect(helper.success_rate_color(100)).to eq("text-emerald-600")
    end

    it "returns amber for good rates (80-94)" do
      expect(helper.success_rate_color(80)).to eq("text-amber-600")
      expect(helper.success_rate_color(85)).to eq("text-amber-600")
      expect(helper.success_rate_color(94)).to eq("text-amber-600")
    end

    it "returns rose for poor rates (below 80)" do
      expect(helper.success_rate_color(0)).to eq("text-rose-600")
      expect(helper.success_rate_color(50)).to eq("text-rose-600")
      expect(helper.success_rate_color(79)).to eq("text-rose-600")
    end

    it "handles edge cases" do
      expect(helper.success_rate_color(79.99)).to eq("text-rose-600")
      expect(helper.success_rate_color(94.99)).to eq("text-amber-600")
    end
  end

  describe "#success_rate_bg", unit: true do
    it "returns slate for nil rate" do
      expect(helper.success_rate_bg(nil)).to eq("bg-slate-100")
    end

    it "returns emerald background for excellent rates" do
      expect(helper.success_rate_bg(95)).to eq("bg-emerald-100")
      expect(helper.success_rate_bg(100)).to eq("bg-emerald-100")
    end

    it "returns amber background for good rates" do
      expect(helper.success_rate_bg(80)).to eq("bg-amber-100")
      expect(helper.success_rate_bg(90)).to eq("bg-amber-100")
    end

    it "returns rose background for poor rates" do
      expect(helper.success_rate_bg(70)).to eq("bg-rose-100")
      expect(helper.success_rate_bg(0)).to eq("bg-rose-100")
    end
  end

  describe "#success_rate_icon_color", unit: true do
    it "returns slate for nil rate" do
      expect(helper.success_rate_icon_color(nil)).to eq("text-slate-600")
    end

    it "returns emerald for excellent rates" do
      expect(helper.success_rate_icon_color(95)).to eq("text-emerald-700")
      expect(helper.success_rate_icon_color(100)).to eq("text-emerald-700")
    end

    it "returns amber for good rates" do
      expect(helper.success_rate_icon_color(80)).to eq("text-amber-700")
      expect(helper.success_rate_icon_color(90)).to eq("text-amber-700")
    end

    it "returns rose for poor rates" do
      expect(helper.success_rate_icon_color(70)).to eq("text-rose-700")
      expect(helper.success_rate_icon_color(0)).to eq("text-rose-700")
    end
  end

  describe "#success_rate_badge", unit: true do
    it "returns slate badge for nil rate" do
      expect(helper.success_rate_badge(nil)).to eq("bg-slate-100 text-slate-600")
    end

    it "returns emerald badge for excellent rates" do
      expect(helper.success_rate_badge(95)).to eq("bg-emerald-100 text-emerald-700")
      expect(helper.success_rate_badge(100)).to eq("bg-emerald-100 text-emerald-700")
    end

    it "returns amber badge for good rates" do
      expect(helper.success_rate_badge(80)).to eq("bg-amber-100 text-amber-700")
      expect(helper.success_rate_badge(90)).to eq("bg-amber-100 text-amber-700")
    end

    it "returns rose badge for poor rates" do
      expect(helper.success_rate_badge(70)).to eq("bg-rose-100 text-rose-700")
      expect(helper.success_rate_badge(0)).to eq("bg-rose-100 text-rose-700")
    end
  end

  describe "color consistency", unit: true do
    it "uses consistent color scheme across success rate methods" do
      rate_95 = 95
      rate_85 = 85
      rate_70 = 70

      expect(helper.success_rate_color(rate_95)).to include("emerald")
      expect(helper.success_rate_bg(rate_95)).to include("emerald")
      expect(helper.success_rate_icon_color(rate_95)).to include("emerald")
      expect(helper.success_rate_badge(rate_95)).to include("emerald")

      expect(helper.success_rate_color(rate_85)).to include("amber")
      expect(helper.success_rate_bg(rate_85)).to include("amber")
      expect(helper.success_rate_icon_color(rate_85)).to include("amber")
      expect(helper.success_rate_badge(rate_85)).to include("amber")

      expect(helper.success_rate_color(rate_70)).to include("rose")
      expect(helper.success_rate_bg(rate_70)).to include("rose")
      expect(helper.success_rate_icon_color(rate_70)).to include("rose")
      expect(helper.success_rate_badge(rate_70)).to include("rose")
    end
  end

  describe "Spanish localization", unit: true do
    it "uses Spanish labels consistently" do
      expect(helper.period_label("last_hour")).to eq("Última hora")
      expect(helper.period_label("last_24_hours")).to eq("Últimas 24 horas")
      expect(helper.period_label("last_7_days")).to eq("Últimos 7 días")
      expect(helper.period_label("last_30_days")).to eq("Últimos 30 días")
    end
  end
end
