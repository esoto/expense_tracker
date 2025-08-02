module ApplicationHelper
  def currency_symbol(expense)
    return "₡" if expense.crc?
    return "$" if expense.usd?
    return "€" if expense.eur?
    "₡" # Default fallback
  end
end
