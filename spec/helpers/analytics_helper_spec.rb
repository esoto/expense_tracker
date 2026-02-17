require "rails_helper"

RSpec.describe AnalyticsHelper, type: :helper, unit: true do
  describe "#format_percentage", unit: true do
    it "returns '0%' for nil value" do
      expect(helper.format_percentage(nil)).to eq("0%")
    end

    it "returns '0%' for zero value" do
      expect(helper.format_percentage(0)).to eq("0%")
    end

    it "formats percentage with default 1 decimal place" do
      expect(helper.format_percentage(75.456)).to eq("75.5%")
    end

    it "formats percentage with custom decimal places" do
      expect(helper.format_percentage(75.456, decimals: 2)).to eq("75.46%")
    end

    it "formats percentage with no decimal places" do
      expect(helper.format_percentage(75.456, decimals: 0)).to eq("75%")
    end

    it "handles integer values" do
      expect(helper.format_percentage(85)).to eq("85%")
    end

    it "handles float values that round to whole numbers" do
      expect(helper.format_percentage(75.0)).to eq("75.0%")
    end
  end

  describe "#performance_color_class", unit: true do
    it "returns emerald for values 80-100" do
      expect(helper.performance_color_class(80)).to eq("text-emerald-600")
      expect(helper.performance_color_class(90)).to eq("text-emerald-600")
      expect(helper.performance_color_class(100)).to eq("text-emerald-600")
    end

    it "returns teal for values 60-79" do
      expect(helper.performance_color_class(60)).to eq("text-teal-600")
      expect(helper.performance_color_class(70)).to eq("text-teal-600")
      expect(helper.performance_color_class(79)).to eq("text-teal-600")
    end

    it "returns amber for values 40-59" do
      expect(helper.performance_color_class(40)).to eq("text-amber-600")
      expect(helper.performance_color_class(50)).to eq("text-amber-600")
      expect(helper.performance_color_class(59)).to eq("text-amber-600")
    end

    it "returns rose for values below 40" do
      expect(helper.performance_color_class(0)).to eq("text-rose-600")
      expect(helper.performance_color_class(20)).to eq("text-rose-600")
      expect(helper.performance_color_class(39)).to eq("text-rose-600")
    end
  end

  describe "#trend_arrow", unit: true do
    it "returns empty string for nil previous value" do
      expect(helper.trend_arrow(100, nil)).to eq("")
    end

    it "returns empty string for zero previous value" do
      expect(helper.trend_arrow(100, 0)).to eq("")
    end

    it "returns upward arrow for positive change" do
      result = helper.trend_arrow(120, 100)
      expect(result).to include("↑ 20.0%")
      expect(result).to include("text-emerald-600")
    end

    it "returns downward arrow for negative change" do
      result = helper.trend_arrow(80, 100)
      expect(result).to include("↓ 20.0%")
      expect(result).to include("text-rose-600")
    end

    it "returns flat arrow for no change" do
      result = helper.trend_arrow(100, 100)
      expect(result).to include("→ 0%")
      expect(result).to include("text-slate-500")
    end

    it "handles decimal values correctly" do
      result = helper.trend_arrow(105.5, 100)
      expect(result).to include("↑ 5.5%")
    end
  end

  describe "#metric_card", unit: true do
    it "renders basic metric card with title and value" do
      result = helper.metric_card(title: "Test Metric", value: "123")

      expect(result).to include("Test Metric")
      expect(result).to include("123")
      expect(result).to include("bg-white rounded-lg shadow-sm")
      expect(result).to include("text-teal-700")
    end

    it "includes subtitle when provided" do
      result = helper.metric_card(title: "Test", value: "123", subtitle: "Last updated")

      expect(result).to include("Last updated")
      expect(result).to include("text-xs text-slate-500")
    end

    it "includes trend when provided" do
      trend = helper.trend_arrow(120, 100)
      result = helper.metric_card(title: "Test", value: "123", trend: trend)

      expect(result).to include("↑ 20.0%")
    end

    it "uses custom color" do
      result = helper.metric_card(title: "Test", value: "123", color: "emerald")

      expect(result).to include("text-emerald-700")
    end
  end

  describe "#progress_bar", unit: true do
    it "renders progress bar with correct percentage" do
      result = helper.progress_bar(75, max: 100)

      expect(result).to include("width: 75%")
      expect(result).to include("bg-teal-600")
      expect(result).to include("bg-slate-200 rounded-full")
    end

    it "handles custom max value" do
      result = helper.progress_bar(50, max: 200)

      expect(result).to include("width: 25%")
    end

    it "handles zero max value" do
      result = helper.progress_bar(50, max: 0)

      expect(result).to include("width: 0%")
    end

    it "uses custom color" do
      result = helper.progress_bar(75, color: "emerald")

      expect(result).to include("bg-emerald-600")
    end

    it "uses custom height" do
      result = helper.progress_bar(75, height: "h-4")

      expect(result).to include("h-4")
    end

    it "handles values exceeding max" do
      result = helper.progress_bar(150, max: 100)

      expect(result).to include("width: 150%")
    end
  end

  describe "#format_number", unit: true do
    it "returns '0' for nil" do
      expect(helper.format_number(nil)).to eq("0")
    end

    it "returns '0' for zero" do
      expect(helper.format_number(0)).to eq("0")
    end

    it "formats numbers under 1000 as-is" do
      expect(helper.format_number(500)).to eq("500")
      expect(helper.format_number(999)).to eq("999")
    end

    it "formats thousands with K suffix" do
      expect(helper.format_number(1000)).to eq("1.0K")
      expect(helper.format_number(1500)).to eq("1.5K")
      expect(helper.format_number(999_999)).to eq("1000.0K")
    end

    it "formats millions with M suffix" do
      expect(helper.format_number(1_000_000)).to eq("1.0M")
      expect(helper.format_number(1_500_000)).to eq("1.5M")
      expect(helper.format_number(10_000_000)).to eq("10.0M")
    end

    it "handles float values" do
      expect(helper.format_number(1234.56)).to eq("1.2K")
    end
  end

  describe "#chart_colors", unit: true do
    it "returns an array of color hex codes" do
      colors = helper.chart_colors

      expect(colors).to be_an(Array)
      expect(colors.length).to eq(8)
      expect(colors.first).to eq("#0F766E")
      expect(colors).to all(start_with("#"))
    end

    it "includes expected color palette" do
      colors = helper.chart_colors

      expect(colors).to include("#0F766E") # teal
      expect(colors).to include("#D97706") # amber
      expect(colors).to include("#FB7185") # rose
      expect(colors).to include("#10B981") # emerald
    end
  end

  describe "#format_duration", unit: true do
    it "returns '0s' for nil" do
      expect(helper.format_duration(nil)).to eq("0s")
    end

    it "returns '0s' for zero" do
      expect(helper.format_duration(0)).to eq("0s")
    end

    it "formats seconds under 60" do
      expect(helper.format_duration(30)).to eq("30s")
      expect(helper.format_duration(59)).to eq("59s")
    end

    it "formats minutes under 60" do
      expect(helper.format_duration(60)).to eq("1m")
      expect(helper.format_duration(150)).to eq("2m")
      expect(helper.format_duration(3599)).to eq("59m")
    end

    it "formats hours under 24" do
      expect(helper.format_duration(3600)).to eq("1h")
      expect(helper.format_duration(7200)).to eq("2h")
      expect(helper.format_duration(86399)).to eq("23h")
    end

    it "formats days" do
      expect(helper.format_duration(86400)).to eq("1d")
      expect(helper.format_duration(172800)).to eq("2d")
      expect(helper.format_duration(604800)).to eq("7d")
    end
  end

  describe "#analytics_status_badge", unit: true do
    it "renders active status with emerald color" do
      result = helper.analytics_status_badge("active")

      expect(result).to include("Active")
      expect(result).to include("bg-emerald-100")
      expect(result).to include("text-emerald-700")
    end

    it "renders processing status with amber color" do
      result = helper.analytics_status_badge("processing")

      expect(result).to include("Processing")
      expect(result).to include("bg-amber-100")
      expect(result).to include("text-amber-700")
    end

    it "renders error status with rose color" do
      result = helper.analytics_status_badge("error")

      expect(result).to include("Error")
      expect(result).to include("bg-rose-100")
      expect(result).to include("text-rose-700")
    end

    it "renders idle status with slate color" do
      result = helper.analytics_status_badge("idle")

      expect(result).to include("Idle")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
    end

    it "handles unknown status with default slate color" do
      result = helper.analytics_status_badge("unknown")

      expect(result).to include("Unknown")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
    end

    it "handles symbol status" do
      result = helper.analytics_status_badge(:active)

      expect(result).to include("Active")
      expect(result).to include("bg-emerald-100")
    end
  end

  describe "#stat_card", unit: true do
    it "renders basic stat card" do
      result = helper.stat_card(label: "Total Users", value: "1,234")

      expect(result).to include("Total Users")
      expect(result).to include("1,234")
      expect(result).to include("bg-white rounded-lg")
      expect(result).to include("text-xs text-slate-500 uppercase")
      expect(result).to include("text-2xl font-bold")
    end

    it "includes change information when provided" do
      result = helper.stat_card(label: "Revenue", value: "$10K", change: "+15%")

      expect(result).to include("+15%")
      expect(result).to include("text-sm")
    end

    it "includes icon when provided" do
      result = helper.stat_card(label: "Users", value: "100", icon: "👤")

      expect(result).to include("👤")
      expect(result).to include("text-slate-400")
    end
  end

  describe "#data_table", unit: true do
    it "renders empty message for no data" do
      result = helper.data_table(headers: [ "Name", "Value" ], rows: [])

      expect(result).to include("No data available")
      expect(result).to include("text-center py-8 text-slate-500")
    end

    it "renders table with headers and rows" do
      headers = [ "Name", "Value" ]
      rows = [ [ "John", "100" ], [ "Jane", "200" ] ]

      result = helper.data_table(headers: headers, rows: rows)

      expect(result).to include("Name")
      expect(result).to include("Value")
      expect(result).to include("John")
      expect(result).to include("Jane")
      expect(result).to include("100")
      expect(result).to include("200")
      expect(result).to include("min-w-full divide-y")
    end

    it "uses custom empty message" do
      result = helper.data_table(headers: [], rows: [], empty_message: "Custom empty message")

      expect(result).to include("Custom empty message")
    end
  end

  describe "#sparkline", unit: true do
    it "returns empty string for blank data" do
      expect(helper.sparkline([])).to eq("")
      expect(helper.sparkline(nil)).to eq("")
    end

    it "renders SVG sparkline for valid data" do
      data = [ 10, 20, 15, 25, 30 ]
      result = helper.sparkline(data)

      expect(result).to include("<svg")
      expect(result).to include("<polyline")
      expect(result).to include("width=\"100\"")
      expect(result).to include("height=\"30\"")
      expect(result).to include("stroke=\"#0F766E\"")
    end

    it "uses custom dimensions and color" do
      data = [ 10, 20, 15 ]
      result = helper.sparkline(data, width: 200, height: 60, color: "#FF0000")

      expect(result).to include("width=\"200\"")
      expect(result).to include("height=\"60\"")
      expect(result).to include("stroke=\"#FF0000\"")
    end

    it "handles single data point" do
      result = helper.sparkline([ 50 ])

      expect(result).to include("<svg")
      expect(result).to include("<polyline")
    end

    it "handles all same values" do
      result = helper.sparkline([ 10, 10, 10 ])

      expect(result).to include("<svg")
      expect(result).to include("<polyline")
    end
  end

  describe "#format_confidence", unit: true do
    it "returns 'N/A' for nil" do
      expect(helper.format_confidence(nil)).to eq("N/A")
    end

    it "formats high confidence with emerald color" do
      result = helper.format_confidence(0.9)

      expect(result).to include("90%")
      expect(result).to include("text-emerald-600")
    end

    it "formats medium confidence with teal color" do
      result = helper.format_confidence(0.7)

      expect(result).to include("70%")
      expect(result).to include("text-teal-600")
    end

    it "formats low confidence with amber color" do
      result = helper.format_confidence(0.5)

      expect(result).to include("50%")
      expect(result).to include("text-amber-600")
    end

    it "formats very low confidence with rose color" do
      result = helper.format_confidence(0.2)

      expect(result).to include("20%")
      expect(result).to include("text-rose-600")
    end

    it "handles edge cases" do
      expect(helper.format_confidence(1.0)).to include("100%")
      expect(helper.format_confidence(0.0)).to include("0%")
    end
  end

  describe "#activity_indicator", unit: true do
    it "returns 'Never' for nil activity" do
      result = helper.activity_indicator(nil)

      expect(result).to include("Never")
      expect(result).to include("text-slate-400")
    end

    it "shows active indicator for recent activity" do
      recent_time = 30.minutes.ago
      result = helper.activity_indicator(recent_time)

      expect(result).to include("Active")
      expect(result).to include("text-emerald-600")
      expect(result).to include("bg-emerald-500")
      expect(result).to include("animate-pulse")
    end

    it "shows normal indicator for activity within a day" do
      recent_time = 2.hours.ago
      result = helper.activity_indicator(recent_time)

      expect(result).to include("text-slate-600")
      expect(result).not_to include("Active")
    end

    it "shows muted indicator for old activity" do
      old_time = 3.days.ago
      result = helper.activity_indicator(old_time)

      expect(result).to include("text-slate-400")
    end
  end

  describe "#heatmap_cell", unit: true do
    it "renders cell with correct intensity colors" do
      # Very high intensity
      result = helper.heatmap_cell(95, max_value: 100)
      expect(result).to include("bg-teal-700")
      expect(result).to include("95")

      # High intensity
      result = helper.heatmap_cell(70, max_value: 100)
      expect(result).to include("bg-teal-600")

      # Medium intensity
      result = helper.heatmap_cell(50, max_value: 100)
      expect(result).to include("bg-teal-500")

      # Low intensity
      result = helper.heatmap_cell(30, max_value: 100)
      expect(result).to include("bg-teal-400")

      # Very low intensity
      result = helper.heatmap_cell(10, max_value: 100)
      expect(result).to include("bg-teal-300")

      # No activity
      result = helper.heatmap_cell(0, max_value: 100)
      expect(result).to include("bg-slate-100")
    end

    it "handles zero max value" do
      result = helper.heatmap_cell(50, max_value: 0)

      expect(result).to include("bg-slate-100")
    end

    it "includes tooltip with occurrence count" do
      result = helper.heatmap_cell(25, max_value: 100)

      expect(result).to include("title=\"25 occurrences\"")
    end

    it "handles float values" do
      result = helper.heatmap_cell(75.5, max_value: 100)

      expect(result).to include("75.5")
    end
  end

  describe "XSS protection", unit: true do
    let(:xss_payload) { '<script>alert("xss")</script>' }
    let(:xss_with_entities) { "&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;" }

    describe "#data_table XSS protection" do
      it "escapes XSS in header values" do
        result = helper.data_table(headers: [ xss_payload ], rows: [ [ "safe" ] ])
        expect(result).not_to include("<script>")
        expect(result).to include(xss_with_entities)
      end

      it "escapes XSS in cell values" do
        result = helper.data_table(headers: [ "Name" ], rows: [ [ xss_payload ] ])
        expect(result).not_to include("<script>")
        expect(result).to include(xss_with_entities)
      end

      it "escapes XSS in both headers and cells simultaneously" do
        result = helper.data_table(
          headers: [ xss_payload ],
          rows: [ [ xss_payload ] ]
        )
        expect(result).not_to include("<script>")
      end

      it "escapes XSS in empty message" do
        result = helper.data_table(headers: [ "Name" ], rows: [], empty_message: xss_payload)
        expect(result).not_to include("<script>")
      end

      it "returns html-safe content from data_table" do
        result = helper.data_table(headers: [ "Name" ], rows: [ [ "value" ] ])
        expect(result).to be_html_safe
      end

      it "handles XSS in multiple rows" do
        result = helper.data_table(
          headers: [ "Name" ],
          rows: [ [ xss_payload ], [ xss_payload ], [ "safe" ] ]
        )
        expect(result).not_to include("<script>")
        expect(result).to include("safe")
      end

      it "handles XSS in multiple cells within a row" do
        result = helper.data_table(
          headers: %w[A B],
          rows: [ [ xss_payload, xss_payload ] ]
        )
        expect(result).not_to include("<script>")
      end

      it "produces correct number of rows" do
        result = helper.data_table(
          headers: %w[Name],
          rows: [ [ "A" ], [ "B" ], [ "C" ] ]
        )
        expect(result.scan("<tr").length).to eq(4) # 1 header + 3 body rows
      end
    end
  end
end
