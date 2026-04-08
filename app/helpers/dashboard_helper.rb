# frozen_string_literal: true

module DashboardHelper
  def relative_date(date)
    case (Date.current - date.to_date).to_i
    when 0 then t("dashboard.v2.today", default: "Today")
    when 1 then t("dashboard.v2.yesterday", default: "Yesterday")
    when 2..6 then l(date.to_date, format: "%A")
    else l(date.to_date, format: :short)
    end
  end
end
