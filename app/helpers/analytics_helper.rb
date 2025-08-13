# frozen_string_literal: true

module AnalyticsHelper
  # Formats percentage value with proper styling
  def format_percentage(value, decimals: 1)
    return "0%" if value.nil? || value.zero?
    "#{value.round(decimals)}%"
  end

  # Returns color class for performance metrics
  def performance_color_class(value)
    case value
    when 80..100
      "text-emerald-600"
    when 60...80
      "text-teal-600"
    when 40...60
      "text-amber-600"
    else
      "text-rose-600"
    end
  end

  # Formats trend arrow with color
  def trend_arrow(current, previous)
    return "" if previous.nil? || previous.zero?

    change = ((current - previous) / previous.to_f * 100).round(1)

    if change > 0
      content_tag(:span, class: "text-emerald-600 text-sm") do
        "↑ #{change}%"
      end
    elsif change < 0
      content_tag(:span, class: "text-rose-600 text-sm") do
        "↓ #{change.abs}%"
      end
    else
      content_tag(:span, "→ 0%", class: "text-slate-500 text-sm")
    end
  end

  # Renders a metric card
  def metric_card(title:, value:, subtitle: nil, trend: nil, color: "teal")
    content_tag :div, class: "bg-white rounded-lg shadow-sm p-6 border border-slate-200" do
      content_tag(:div, class: "flex items-start justify-between") do
        content_tag(:div) do
          content_tag(:p, title, class: "text-sm font-medium text-slate-600") +
          content_tag(:p, value, class: "mt-1 text-3xl font-semibold text-#{color}-700") +
          (subtitle ? content_tag(:p, subtitle, class: "mt-1 text-xs text-slate-500") : "") +
          (trend ? content_tag(:div, trend, class: "mt-2") : "")
        end
      end
    end
  end

  # Renders a progress bar
  def progress_bar(value, max: 100, color: "teal", height: "h-2")
    percentage = max > 0 ? (value.to_f / max * 100).round : 0

    content_tag :div, class: "w-full bg-slate-200 rounded-full #{height}" do
      content_tag :div, "",
                  class: "bg-#{color}-600 #{height} rounded-full transition-all duration-300",
                  style: "width: #{percentage}%"
    end
  end

  # Formats large numbers with abbreviations
  def format_number(number)
    return "0" if number.nil? || number.zero?

    if number >= 1_000_000
      "#{(number / 1_000_000.0).round(1)}M"
    elsif number >= 1_000
      "#{(number / 1_000.0).round(1)}K"
    else
      number.to_s
    end
  end

  # Returns chart color palette
  def chart_colors
    %w[#0F766E #D97706 #FB7185 #10B981 #6366F1 #8B5CF6 #EC4899 #F59E0B]
  end

  # Formats time duration
  def format_duration(seconds)
    return "0s" if seconds.nil? || seconds.zero?

    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m"
    elsif seconds < 86400
      "#{(seconds / 3600).round}h"
    else
      "#{(seconds / 86400).round}d"
    end
  end

  # Returns status badge for analytics
  def analytics_status_badge(status)
    colors = {
      "active" => "emerald",
      "processing" => "amber",
      "error" => "rose",
      "idle" => "slate"
    }

    color = colors[status.to_s] || "slate"

    content_tag :span, status.to_s.humanize,
                class: "px-2 py-1 text-xs rounded-full bg-#{color}-100 text-#{color}-700"
  end

  # Renders a stat card for dashboards
  def stat_card(label:, value:, icon: nil, change: nil)
    content_tag :div, class: "bg-white rounded-lg p-4 border border-slate-200" do
      content_tag(:div, class: "flex items-center justify-between") do
        content_tag(:div) do
          content_tag(:p, label, class: "text-xs text-slate-500 uppercase tracking-wide") +
          content_tag(:p, value, class: "mt-1 text-2xl font-bold text-slate-900") +
          (change ? content_tag(:p, change, class: "mt-1 text-sm") : "")
        end +
        (icon ? content_tag(:div, icon, class: "text-slate-400") : "")
      end
    end
  end

  # Renders a data table
  def data_table(headers:, rows:, empty_message: "No data available")
    if rows.empty?
      content_tag :div, empty_message, class: "text-center py-8 text-slate-500"
    else
      content_tag :table, class: "min-w-full divide-y divide-slate-200" do
        content_tag(:thead, class: "bg-slate-50") do
          content_tag(:tr) do
            headers.map do |header|
              content_tag(:th, header,
                         class: "px-6 py-3 text-left text-xs font-medium text-slate-500 uppercase tracking-wider")
            end.join.html_safe
          end
        end +
        content_tag(:tbody, class: "bg-white divide-y divide-slate-200") do
          rows.map do |row|
            content_tag(:tr) do
              row.map do |cell|
                content_tag(:td, cell, class: "px-6 py-4 whitespace-nowrap text-sm text-slate-900")
              end.join.html_safe
            end
          end.join.html_safe
        end
      end
    end
  end

  # Returns a sparkline chart
  def sparkline(data, width: 100, height: 30, color: "#0F766E")
    return "" if data.blank?

    max_value = data.max.to_f
    min_value = data.min.to_f
    range = max_value - min_value
    range = 1 if range.zero?

    points = data.each_with_index.map do |value, index|
      x = (index.to_f / (data.length - 1) * width).round(2)
      y = height - ((value - min_value) / range * height).round(2)
      "#{x},#{y}"
    end.join(" ")

    content_tag :svg, width: width, height: height, class: "inline-block" do
      content_tag :polyline, nil,
                  points: points,
                  fill: "none",
                  stroke: color,
                  "stroke-width": 2
    end
  end

  # Formats confidence score
  def format_confidence(score)
    return "N/A" if score.nil?

    color = case score
    when 0.8..1.0 then "emerald"
    when 0.6...0.8 then "teal"
    when 0.4...0.6 then "amber"
    else "rose"
    end

    content_tag :span, "#{(score * 100).round}%",
                class: "font-medium text-#{color}-600"
  end

  # Returns activity indicator
  def activity_indicator(last_activity)
    return content_tag(:span, "Never", class: "text-slate-400") if last_activity.nil?

    time_ago = time_ago_in_words(last_activity)

    if last_activity > 1.hour.ago
      content_tag :span, class: "flex items-center" do
        content_tag(:span, "", class: "w-2 h-2 bg-emerald-500 rounded-full mr-2 animate-pulse") +
        content_tag(:span, "Active #{time_ago} ago", class: "text-emerald-600 text-sm")
      end
    elsif last_activity > 1.day.ago
      content_tag :span, "#{time_ago} ago", class: "text-slate-600 text-sm"
    else
      content_tag :span, "#{time_ago} ago", class: "text-slate-400 text-sm"
    end
  end

  # Renders a heatmap cell
  def heatmap_cell(value, max_value: 100)
    intensity = max_value > 0 ? (value.to_f / max_value * 100).round : 0

    color = case intensity
    when 80..100 then "bg-teal-700"
    when 60...80 then "bg-teal-600"
    when 40...60 then "bg-teal-500"
    when 20...40 then "bg-teal-400"
    when 1...20 then "bg-teal-300"
    else "bg-slate-100"
    end

    content_tag :div, value.to_s,
                class: "#{color} text-white text-xs p-2 rounded text-center",
                title: "#{value} occurrences"
  end
end
