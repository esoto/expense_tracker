# frozen_string_literal: true

# Helper methods for budget views and progress indicators
module BudgetsHelper
  # Returns the appropriate color class for the progress bar based on budget status
  def progress_bar_color_class(status)
    case status
    when :exceeded
      "bg-rose-600"
    when :critical
      "bg-rose-500"
    when :warning
      "bg-amber-600"
    else
      "bg-emerald-600"
    end
  end

  # Returns the appropriate text color class for remaining amount display
  def remaining_amount_color_class(status)
    case status
    when :exceeded, :critical
      "text-rose-600"
    when :warning
      "text-amber-600"
    else
      "text-emerald-600"
    end
  end

  # Returns the appropriate text color class for status text
  def status_text_color_class(status)
    case status
    when :exceeded, :critical
      "text-rose-700"
    when :warning
      "text-amber-700"
    else
      "text-emerald-700"
    end
  end

  # Generates the appropriate status icon based on budget status
  def status_icon(status)
    case status
    when :exceeded
      content_tag :svg, class: "w-4 h-4 text-rose-600", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
        content_tag :path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
                    d: "M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      end
    when :critical
      content_tag :svg, class: "w-4 h-4 text-rose-500", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
        content_tag :path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
                    d: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      end
    when :warning
      content_tag :svg, class: "w-4 h-4 text-amber-600", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
        content_tag :path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2",
                    d: "M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
      end
    else
      content_tag :svg, class: "w-4 h-4 text-emerald-600", fill: "currentColor", viewBox: "0 0 20 20" do
        content_tag :path, nil, "fill-rule": "evenodd",
                    d: "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z",
                    "clip-rule": "evenodd"
      end
    end
  end

  # Converts a period label in Spanish to the corresponding period type
  def period_from_label(label)
    case label
    when /Mes/i
      "monthly"
    when /Semana/i
      "weekly"
    when /Hoy|Día/i
      "daily"
    when /Año/i
      "yearly"
    else
      "monthly"
    end
  end
end
