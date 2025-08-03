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
end
