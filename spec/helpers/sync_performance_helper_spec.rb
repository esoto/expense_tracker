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

  describe "#format_metric_duration", unit: true do
    it "returns dash for nil duration" do
      expect(helper.format_metric_duration(nil)).to eq("-")
    end

    it "formats milliseconds under 1000" do
      expect(helper.format_metric_duration(500)).to eq("500 ms")
      expect(helper.format_metric_duration(999)).to eq("999 ms")
      expect(helper.format_metric_duration(0)).to eq("0 ms")
    end

    it "formats seconds under 60000 ms (1 minute)" do
      expect(helper.format_metric_duration(1000)).to eq("1.0 s")
      expect(helper.format_metric_duration(1500)).to eq("1.5 s")
      expect(helper.format_metric_duration(30000)).to eq("30.0 s")
      expect(helper.format_metric_duration(59999)).to eq("60.0 s")
    end

    it "formats minutes for 60000 ms and above" do
      expect(helper.format_metric_duration(60000)).to eq("1.0 min")
      expect(helper.format_metric_duration(90000)).to eq("1.5 min")
      expect(helper.format_metric_duration(300000)).to eq("5.0 min")
    end

    it "rounds milliseconds to whole numbers" do
      expect(helper.format_metric_duration(123.456)).to eq("123 ms")
      expect(helper.format_metric_duration(999.9)).to eq("1000 ms")
    end

    it "rounds seconds to 2 decimal places" do
      expect(helper.format_metric_duration(1234)).to eq("1.23 s")
      expect(helper.format_metric_duration(12345)).to eq("12.35 s")
    end
  end

  describe "#format_timestamp", unit: true do
    it "returns dash for nil timestamp" do
      expect(helper.format_timestamp(nil)).to eq("-")
    end

    it "returns time ago for recent timestamps (within 24 hours)" do
      recent_time = 2.hours.ago
      result = helper.format_timestamp(recent_time)

      expect(result).to include("atrás")
      expect(result).to include("hours") # time_ago_in_words returns English
    end

    it "returns formatted date for older timestamps (beyond 24 hours)" do
      old_time = 3.days.ago
      result = helper.format_timestamp(old_time)

      expect(result).to match(/\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}/)
      expect(result).not_to include("atrás")
    end

    it "handles edge case of exactly 24 hours ago" do
      exactly_24h = 24.hours.ago - 1.second
      result = helper.format_timestamp(exactly_24h)

      expect(result).to match(/\d{2}\/\d{2}\/\d{4} \d{2}:\d{2}/)
    end

    it "handles very recent timestamps" do
      very_recent = 5.minutes.ago
      result = helper.format_timestamp(very_recent)

      expect(result).to include("atrás")
      expect(result).to include("minutes") # time_ago_in_words returns English
    end
  end

  describe "#processing_rate_indicator", unit: true do
    it "returns slate for nil rate" do
      expect(helper.processing_rate_indicator(nil)).to eq("text-slate-400")
    end

    it "returns slate for zero rate" do
      expect(helper.processing_rate_indicator(0)).to eq("text-slate-400")
    end

    it "returns rose for very low rates (0 to <1)" do
      expect(helper.processing_rate_indicator(0.5)).to eq("text-rose-600")
      expect(helper.processing_rate_indicator(0.99)).to eq("text-rose-600")
    end

    it "returns amber for low rates (1 to <5)" do
      expect(helper.processing_rate_indicator(1)).to eq("text-amber-600")
      expect(helper.processing_rate_indicator(3)).to eq("text-amber-600")
      expect(helper.processing_rate_indicator(4.99)).to eq("text-amber-600")
    end

    it "returns emerald for good rates (5 and above)" do
      expect(helper.processing_rate_indicator(5)).to eq("text-emerald-600")
      expect(helper.processing_rate_indicator(10)).to eq("text-emerald-600")
      expect(helper.processing_rate_indicator(100)).to eq("text-emerald-600")
    end
  end

  describe "#error_severity_badge", unit: true do
    it "returns warning badge for timeout errors" do
      expect(helper.error_severity_badge("timeout error")).to eq("bg-amber-100 text-amber-700")
      expect(helper.error_severity_badge("CONNECTION_TIMEOUT")).to eq("bg-amber-100 text-amber-700")
    end

    it "returns warning badge for connection errors" do
      expect(helper.error_severity_badge("connection failed")).to eq("bg-amber-100 text-amber-700")
      expect(helper.error_severity_badge("Connection Error")).to eq("bg-amber-100 text-amber-700")
    end

    it "returns critical badge for authentication errors" do
      expect(helper.error_severity_badge("authentication failed")).to eq("bg-rose-100 text-rose-700")
      expect(helper.error_severity_badge("AUTHENTICATION_ERROR")).to eq("bg-rose-100 text-rose-700")
    end

    it "returns critical badge for permission errors" do
      expect(helper.error_severity_badge("permission denied")).to eq("bg-rose-100 text-rose-700")
      expect(helper.error_severity_badge("PERMISSION_ERROR")).to eq("bg-rose-100 text-rose-700")
    end

    it "returns info badge for parse errors" do
      expect(helper.error_severity_badge("parse error")).to eq("bg-slate-100 text-slate-700")
      expect(helper.error_severity_badge("FORMAT_ERROR")).to eq("bg-slate-100 text-slate-700")
    end

    it "returns normal badge for unknown error types" do
      expect(helper.error_severity_badge("unknown error")).to eq("bg-slate-100 text-slate-600")
      expect(helper.error_severity_badge("some random error")).to eq("bg-slate-100 text-slate-600")
    end

    it "handles nil error type" do
      expect(helper.error_severity_badge(nil)).to eq("bg-slate-100 text-slate-600")
    end

    it "handles empty string error type" do
      expect(helper.error_severity_badge("")).to eq("bg-slate-100 text-slate-600")
    end
  end

  describe "#chart_color_scheme", unit: true do
    it "returns hash with expected color keys" do
      colors = helper.chart_color_scheme

      expect(colors).to be_a(Hash)
      expect(colors.keys).to contain_exactly(:primary, :success, :warning, :error, :neutral)
    end

    it "returns RGB color values" do
      colors = helper.chart_color_scheme

      expect(colors[:primary]).to eq("rgb(15, 118, 110)")
      expect(colors[:success]).to eq("rgb(16, 185, 129)")
      expect(colors[:warning]).to eq("rgb(217, 119, 6)")
      expect(colors[:error]).to eq("rgb(251, 113, 133)")
      expect(colors[:neutral]).to eq("rgb(100, 116, 139)")
    end

    it "uses consistent color scheme with Tailwind CSS colors" do
      colors = helper.chart_color_scheme

      # Verify these match the expected Tailwind colors
      expect(colors[:primary]).to include("15, 118, 110") # teal-700
      expect(colors[:success]).to include("16, 185, 129") # emerald-500
      expect(colors[:warning]).to include("217, 119, 6")  # amber-600
      expect(colors[:error]).to include("251, 113, 133")  # rose-400
      expect(colors[:neutral]).to include("100, 116, 139") # slate-500
    end
  end

  describe "#performance_trend_icon", unit: true do
    it "returns empty string for nil current value" do
      expect(helper.performance_trend_icon(nil, 100)).to eq("")
    end

    it "returns empty string for nil previous value" do
      expect(helper.performance_trend_icon(100, nil)).to eq("")
    end

    it "returns empty string for zero previous value" do
      expect(helper.performance_trend_icon(100, 0)).to eq("")
    end

    it "returns upward trend for significant improvement (>5%)" do
      result = helper.performance_trend_icon(110, 100)

      expect(result).to include("text-emerald-600")
      expect(result).to include("+10.0%")
      expect(result).to include("svg")
      expect(result).to include("M5 10l7-7m0 0l7 7m-7-7v18") # up arrow path
    end

    it "returns downward trend for significant decline (<-5%)" do
      result = helper.performance_trend_icon(85, 100)

      expect(result).to include("text-rose-600")
      expect(result).to include("-15.0%")
      expect(result).to include("svg")
      expect(result).to include("M19 14l-7 7m0 0l-7-7m7 7V3") # down arrow path
    end

    it "returns neutral trend for small changes (-5% to 5%)" do
      result = helper.performance_trend_icon(103, 100)

      expect(result).to include("text-slate-500")
      expect(result).to include("3.0%")
      expect(result).to include("svg")
      expect(result).to include("M5 12h14") # horizontal line path
    end

    it "handles edge cases of exactly ±5%" do
      # Exactly +5% (should be neutral)
      result_up = helper.performance_trend_icon(105, 100)
      expect(result_up).to include("text-slate-500")

      # Exactly -5% (should be neutral)
      result_down = helper.performance_trend_icon(95, 100)
      expect(result_down).to include("text-slate-500")
    end

    it "calculates percentage change correctly" do
      result = helper.performance_trend_icon(120.5, 100)
      expect(result).to include("+20.5%")

      result = helper.performance_trend_icon(87.25, 100)
      expect(result).to include("-12.75%")
    end
  end

  describe "#queue_depth_status", unit: true do
    it "returns empty status for depth 0" do
      result = helper.queue_depth_status(0)

      expect(result[:label]).to eq("Vacía")
      expect(result[:color]).to eq("text-emerald-600")
      expect(result[:bg]).to eq("bg-emerald-100")
    end

    it "returns normal status for depth 1-10" do
      [ 1, 5, 10 ].each do |depth|
        result = helper.queue_depth_status(depth)

        expect(result[:label]).to eq("Normal")
        expect(result[:color]).to eq("text-teal-600")
        expect(result[:bg]).to eq("bg-teal-100")
      end
    end

    it "returns moderate status for depth 11-50" do
      [ 11, 25, 50 ].each do |depth|
        result = helper.queue_depth_status(depth)

        expect(result[:label]).to eq("Moderada")
        expect(result[:color]).to eq("text-amber-600")
        expect(result[:bg]).to eq("bg-amber-100")
      end
    end

    it "returns high status for depth above 50" do
      [ 51, 100, 1000 ].each do |depth|
        result = helper.queue_depth_status(depth)

        expect(result[:label]).to eq("Alta")
        expect(result[:color]).to eq("text-rose-600")
        expect(result[:bg]).to eq("bg-rose-100")
      end
    end

    it "returns hash with expected keys" do
      result = helper.queue_depth_status(25)

      expect(result.keys).to contain_exactly(:label, :color, :bg)
      expect(result[:label]).to be_a(String)
      expect(result[:color]).to be_a(String)
      expect(result[:bg]).to be_a(String)
    end
  end

  describe "color consistency", unit: true do
    it "uses consistent color scheme across all methods" do
      # Test that all methods use the same color classes
      rate_95 = 95
      rate_85 = 85
      rate_70 = 70

      # Success rate methods should use consistent colors
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

    it "follows the financial confidence color palette" do
      # Verify colors match the expected palette from CLAUDE.md
      colors = helper.chart_color_scheme

      expect(colors[:primary]).to include("15, 118, 110") # teal-700
      expect(colors[:success]).to include("16, 185, 129") # emerald-500
      expect(colors[:warning]).to include("217, 119, 6")  # amber-600
      expect(colors[:error]).to include("251, 113, 133")  # rose-400
    end
  end

  describe "Spanish localization", unit: true do
    it "uses Spanish labels consistently" do
      expect(helper.period_label("last_hour")).to eq("Última hora")
      expect(helper.period_label("last_24_hours")).to eq("Últimas 24 horas")
      expect(helper.period_label("last_7_days")).to eq("Últimos 7 días")
      expect(helper.period_label("last_30_days")).to eq("Últimos 30 días")

      expect(helper.queue_depth_status(0)[:label]).to eq("Vacía")
      expect(helper.queue_depth_status(25)[:label]).to eq("Moderada")
      expect(helper.queue_depth_status(100)[:label]).to eq("Alta")
    end

    it "uses 'atrás' suffix for recent timestamps" do
      recent = 1.hour.ago
      result = helper.format_timestamp(recent)

      expect(result).to include("atrás")
    end
  end
end
