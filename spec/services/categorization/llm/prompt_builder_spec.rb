# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Llm::PromptBuilder, :unit do
  subject(:builder) { described_class.new }

  let(:expense) do
    build(:expense, merchant_name: "McDonald's", description: "Compra en restaurante",
                    amount: 5500.0, currency: "crc")
  end

  let(:category_keys) { %w[food restaurants supermarket coffee_shop transport utilities] }
  let(:not_relation) { double("ActiveRecord::Relation", pluck: category_keys) }
  let(:where_relation) { double("ActiveRecord::Relation", not: not_relation) }

  before do
    allow(Category).to receive(:where).and_return(where_relation)
  end

  describe "#build" do
    it "includes the system instruction" do
      result = builder.build(expense: expense)

      expect(result).to include("You are an expense categorizer")
      expect(result).to include("Return ONLY the category key")
    end

    it "includes dynamically generated categories from the database" do
      result = builder.build(expense: expense)

      expect(result).to include("Categories:")
      category_keys.each do |key|
        expect(result).to include(key)
      end
    end

    it "includes merchant name from the expense" do
      result = builder.build(expense: expense)

      expect(result).to include("Merchant: McDonald's")
    end

    it "includes description from the expense" do
      result = builder.build(expense: expense)

      expect(result).to include("Description: Compra en restaurante")
    end

    it "includes amount and currency from the expense" do
      result = builder.build(expense: expense)

      expect(result).to include("Amount: 5500.0 crc")
    end

    it "handles expenses with nil description" do
      expense.description = nil
      result = builder.build(expense: expense)

      expect(result).to include("Description: ")
    end

    it "handles expenses with nil merchant_name" do
      expense.merchant_name = nil
      result = builder.build(expense: expense)

      expect(result).to include("Merchant: ")
    end

    context "when correction_history is provided" do
      let(:correction_history) { { old: "food", new: "restaurants" } }

      it "appends the correction note to the prompt" do
        result = builder.build(expense: expense, correction_history: correction_history)

        expect(result).to include(
          "Note: This merchant was previously categorized as food but corrected to restaurants by the user."
        )
      end
    end

    context "when correction_history is nil" do
      it "does not include a correction note" do
        result = builder.build(expense: expense, correction_history: nil)

        expect(result).not_to include("Note:")
      end
    end

    context "when no categories exist in the database" do
      let(:not_relation) { double("ActiveRecord::Relation", pluck: []) }

      it "builds the prompt with an empty categories list" do
        result = builder.build(expense: expense)

        expect(result).to include("Categories:")
        expect(result).to include("Expense:")
      end
    end
  end
end
