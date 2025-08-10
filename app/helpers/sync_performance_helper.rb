module SyncPerformanceHelper
  def period_label(period)
    case period
    when "last_hour"
      "Última hora"
    when "last_24_hours"
      "Últimas 24 horas"
    when "last_7_days"
      "Últimos 7 días"
    when "last_30_days"
      "Últimos 30 días"
    else
      "Personalizado"
    end
  end

  def success_rate_color(rate)
    return "text-slate-400" if rate.nil?

    case rate
    when 95..100
      "text-emerald-600"
    when 80...95
      "text-amber-600"
    else
      "text-rose-600"
    end
  end

  def success_rate_bg(rate)
    return "bg-slate-100" if rate.nil?

    case rate
    when 95..100
      "bg-emerald-100"
    when 80...95
      "bg-amber-100"
    else
      "bg-rose-100"
    end
  end

  def success_rate_icon_color(rate)
    return "text-slate-600" if rate.nil?

    case rate
    when 95..100
      "text-emerald-700"
    when 80...95
      "text-amber-700"
    else
      "text-rose-700"
    end
  end

  def success_rate_badge(rate)
    return "bg-slate-100 text-slate-600" if rate.nil?

    case rate
    when 95..100
      "bg-emerald-100 text-emerald-700"
    when 80...95
      "bg-amber-100 text-amber-700"
    else
      "bg-rose-100 text-rose-700"
    end
  end

  def format_metric_duration(duration_ms)
    return "-" if duration_ms.nil?

    if duration_ms < 1000
      "#{duration_ms.round(0)} ms"
    elsif duration_ms < 60000
      "#{(duration_ms / 1000.0).round(2)} s"
    else
      "#{(duration_ms / 60000.0).round(2)} min"
    end
  end

  def format_timestamp(timestamp)
    return "-" if timestamp.nil?

    if timestamp > 24.hours.ago
      "#{time_ago_in_words(timestamp)} atrás"
    else
      timestamp.strftime("%d/%m/%Y %H:%M")
    end
  end

  def processing_rate_indicator(rate)
    return "text-slate-400" if rate.nil? || rate.zero?

    case rate
    when 0...1
      "text-rose-600"
    when 1...5
      "text-amber-600"
    else
      "text-emerald-600"
    end
  end

  def error_severity_badge(error_type)
    severity = case error_type
    when /timeout/i, /connection/i
      "warning"
    when /authentication/i, /permission/i
      "critical"
    when /parse/i, /format/i
      "info"
    else
      "normal"
    end

    case severity
    when "critical"
      "bg-rose-100 text-rose-700"
    when "warning"
      "bg-amber-100 text-amber-700"
    when "info"
      "bg-slate-100 text-slate-700"
    else
      "bg-slate-100 text-slate-600"
    end
  end

  def chart_color_scheme
    {
      primary: "rgb(15, 118, 110)", # teal-700
      success: "rgb(16, 185, 129)", # emerald-500
      warning: "rgb(217, 119, 6)",  # amber-600
      error: "rgb(251, 113, 133)",  # rose-400
      neutral: "rgb(100, 116, 139)" # slate-500
    }
  end

  def performance_trend_icon(current, previous)
    return "" if current.nil? || previous.nil? || previous.zero?

    change = ((current - previous) / previous.to_f * 100).round(2)

    if change > 5
      content_tag(:span, class: "inline-flex items-center text-emerald-600") do
        concat(content_tag(:svg, class: "h-4 w-4 mr-1", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
          content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M5 10l7-7m0 0l7 7m-7-7v18")
        end)
        concat("+#{change}%")
      end
    elsif change < -5
      content_tag(:span, class: "inline-flex items-center text-rose-600") do
        concat(content_tag(:svg, class: "h-4 w-4 mr-1", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
          content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M19 14l-7 7m0 0l-7-7m7 7V3")
        end)
        concat("#{change}%")
      end
    else
      content_tag(:span, class: "inline-flex items-center text-slate-500") do
        concat(content_tag(:svg, class: "h-4 w-4 mr-1", fill: "none", stroke: "currentColor", viewBox: "0 0 24 24") do
          content_tag(:path, nil, "stroke-linecap": "round", "stroke-linejoin": "round", "stroke-width": "2", d: "M5 12h14")
        end)
        concat("#{change.abs}%")
      end
    end
  end

  def queue_depth_status(depth)
    case depth
    when 0
      { label: "Vacía", color: "text-emerald-600", bg: "bg-emerald-100" }
    when 1..10
      { label: "Normal", color: "text-teal-600", bg: "bg-teal-100" }
    when 11..50
      { label: "Moderada", color: "text-amber-600", bg: "bg-amber-100" }
    else
      { label: "Alta", color: "text-rose-600", bg: "bg-rose-100" }
    end
  end
end
