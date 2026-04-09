# frozen_string_literal: true

module AnalyticsHelper
  # Accessible chart color palette using design system colors.
  # Chosen for sufficient contrast between adjacent segments
  # and distinguishability for colorblind users (deuteranopia, protanopia).
  def chart_colors
    %w[#0F766E #D97706 #0D9488 #E11D48 #059669 #475569 #0891B2 #9333EA]
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
end
