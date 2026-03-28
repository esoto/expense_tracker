# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Budget period i18n translations", :unit do
  describe "Spanish (es) translations" do
    around do |example|
      I18n.with_locale(:es) { example.run }
    end

    it "translates daily period" do
      expect(I18n.t("budgets.periods.daily")).to eq("Diario")
    end

    it "translates weekly period" do
      expect(I18n.t("budgets.periods.weekly")).to eq("Semanal")
    end

    it "translates monthly period" do
      expect(I18n.t("budgets.periods.monthly")).to eq("Mensual")
    end

    it "translates yearly period" do
      expect(I18n.t("budgets.periods.yearly")).to eq("Anual")
    end

    it "does not return a missing translation string for any period" do
      Budget.periods.each_key do |period|
        translation = I18n.t("budgets.periods.#{period}")
        expect(translation).not_to include("translation missing"), \
          "Expected translation for 'budgets.periods.#{period}' to exist in es locale"
      end
    end
  end

  describe "English (en) translations" do
    around do |example|
      I18n.with_locale(:en) { example.run }
    end

    it "translates daily period" do
      expect(I18n.t("budgets.periods.daily")).to eq("Daily")
    end

    it "translates weekly period" do
      expect(I18n.t("budgets.periods.weekly")).to eq("Weekly")
    end

    it "translates monthly period" do
      expect(I18n.t("budgets.periods.monthly")).to eq("Monthly")
    end

    it "translates yearly period" do
      expect(I18n.t("budgets.periods.yearly")).to eq("Yearly")
    end

    it "does not return a missing translation string for any period" do
      Budget.periods.each_key do |period|
        translation = I18n.t("budgets.periods.#{period}")
        expect(translation).not_to include("translation missing"), \
          "Expected translation for 'budgets.periods.#{period}' to exist in en locale"
      end
    end
  end
end
