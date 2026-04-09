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
end
