module ApplicationHelper
  def currency_symbol(expense)
    return "₡" if expense.crc?
    return "$" if expense.usd?
    return "€" if expense.eur?
    "₡" # Default fallback
  end

  def format_datetime(datetime)
    return "N/A" if datetime.blank?
    datetime.strftime("%B %d, %Y at %I:%M %p")
  end

  def format_date(date)
    return "N/A" if date.blank?
    date.strftime("%B %d, %Y")
  end

  def flash_css_class(type)
    case type.to_sym
    when :notice, :success
      "bg-emerald-50 border border-emerald-200 text-emerald-700"
    when :alert, :error
      "bg-rose-50 border border-rose-200 text-rose-700"
    when :warning
      "bg-amber-50 border border-amber-200 text-amber-700"
    else
      "bg-slate-50 border border-slate-200 text-slate-700"
    end
  end
end
