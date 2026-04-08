# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardHelper, type: :helper, unit: true do
  describe "#relative_date" do
    it "returns 'Today' for today's date" do
      expect(helper.relative_date(Date.current)).to eq("Today")
    end

    it "returns 'Yesterday' for yesterday's date" do
      expect(helper.relative_date(Date.current - 1.day)).to eq("Yesterday")
    end

    it "returns the day name for dates 2-6 days ago" do
      date = Date.current - 3.days
      expected_day_name = I18n.l(date, format: "%A")
      expect(helper.relative_date(date)).to eq(expected_day_name)
    end

    it "returns short formatted date for dates older than 6 days" do
      date = Date.current - 14.days
      expected_format = I18n.l(date, format: :short)
      expect(helper.relative_date(date)).to eq(expected_format)
    end

    it "handles Time objects by converting to date" do
      expect(helper.relative_date(Time.current)).to eq("Today")
    end
  end
end
