# frozen_string_literal: true

require "rails_helper"

RSpec.describe BudgetCategory, type: :model, unit: true do
  describe "associations" do
    it { is_expected.to belong_to(:budget) }
    it { is_expected.to belong_to(:category) }
  end

  describe "validations" do
    it "rejects duplicate (budget, category) pairs" do
      budget = create(:budget)
      category = create(:category, name: "Food")
      described_class.create!(budget: budget, category: category)
      dup = described_class.new(budget: budget, category: category)

      expect(dup).not_to be_valid
      expect(dup.errors[:budget_id]).to include(I18n.t("errors.messages.taken"))
    end
  end
end
