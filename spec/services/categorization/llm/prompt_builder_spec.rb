# frozen_string_literal: true

require "rails_helper"

RSpec.describe Services::Categorization::Llm::PromptBuilder, :unit do
  subject(:builder) { described_class.new }

  let(:expense) do
    build(:expense, merchant_name: "McDonald's", description: "Compra en restaurante",
                    amount: 5500.0, currency: "crc", bank_name: "BAC",
                    email_body: "Comercio: McDonald's Ciudad y país: SAN JOSE, Costa Rica Fecha: Ene 5, 2026")
  end

  let(:category_data) do
    [
      %w[food Alimentación],
      %w[restaurants Restaurantes],
      %w[supermarket Supermercado],
      %w[coffee_shop Cafetería],
      %w[transport Transporte],
      %w[utilities Servicios]
    ]
  end
  let(:not_relation) { double("ActiveRecord::Relation", pluck: category_data) }
  let(:where_relation) { double("ActiveRecord::Relation", not: not_relation) }

  before do
    allow(Category).to receive(:where).and_return(where_relation)
  end

  describe "#build" do
    it "includes the system instruction" do
      result = builder.build(expense: expense)

      expect(result).to include("local business expert")
      expect(result).to include("ONLY the category key")
    end

    it "includes categories with Spanish display names" do
      result = builder.build(expense: expense)

      expect(result).to include("Categories:")
      expect(result).to include("- food (Alimentación)")
      expect(result).to include("- restaurants (Restaurantes)")
    end

    it "includes merchant name from the expense" do
      result = builder.build(expense: expense)

      expect(result).to include("Merchant: McDonald's")
    end

    it "includes bank name" do
      result = builder.build(expense: expense)

      expect(result).to include("Bank: BAC")
    end

    it "includes formatted amount with currency" do
      result = builder.build(expense: expense)

      expect(result).to include("Amount: 5,500.0 CRC")
    end

    it "extracts and includes location from email body" do
      result = builder.build(expense: expense)

      expect(result).to include("Location: SAN JOSE, Costa Rica")
    end

    it "handles expenses with nil merchant_name" do
      expense.merchant_name = nil
      result = builder.build(expense: expense)

      expect(result).not_to include("Merchant:")
    end

    it "handles expenses with nil bank_name" do
      expense.bank_name = nil
      result = builder.build(expense: expense)

      expect(result).not_to include("Bank:")
    end

    it "handles Pais no Definido as nil country" do
      expense.email_body = "Comercio: Apple Ciudad y país: CUPERTNO, Pais no Definido Fecha: Ene 5, 2026"
      result = builder.build(expense: expense)

      expect(result).to include("Location: CUPERTNO")
      expect(result).not_to include("Pais no Definido")
    end

    it "handles expenses with no email body" do
      expense.email_body = nil
      expense.raw_email_content = nil
      result = builder.build(expense: expense)

      expect(result).not_to include("Location:")
    end

    it "includes payment processor guidance in system instruction" do
      result = builder.build(expense: expense)

      expect(result).to include("payment processor")
      expect(result).to include("uncategorized")
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
        expect(result).to include("Transaction:")
      end
    end
  end
end
