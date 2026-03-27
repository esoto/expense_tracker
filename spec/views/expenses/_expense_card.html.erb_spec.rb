require "rails_helper"

RSpec.describe "expenses/_expense_card.html.erb", type: :view, unit: true do
  let(:category) { create(:category, name: "Alimentación", color: "#FF6B6B") }
  let(:processed_expense) do
    create(:expense,
      merchant_name: "Super Mas",
      amount: 15000.50,
      transaction_date: Date.new(2026, 3, 15),
      status: "processed",
      category: category)
  end
  let(:pending_expense) do
    create(:expense,
      merchant_name: "McDonald's",
      amount: 3500.00,
      transaction_date: Date.new(2026, 3, 20),
      status: "pending",
      category: category)
  end
  let(:categories) { [ category ] }

  describe "merchant name and amount display" do
    before do
      render partial: "expenses/expense_card",
             locals: { expense: processed_expense, categories: categories }
    end

    it "renders the merchant name" do
      expect(rendered).to have_content("Super Mas")
    end

    it "renders the formatted amount" do
      # Rails uses locale number formatting — in :es locale, thousands separator is "."
      expect(rendered).to have_content("15")
      expect(rendered).to have_content("000")
    end

    it "renders the transaction date formatted as dd/mm/yyyy" do
      expect(rendered).to have_content("15/03/2026")
    end

    it "renders the category name" do
      expect(rendered).to have_content("Alimentación")
    end
  end

  describe "status badge visibility" do
    context "when expense status is processed" do
      before do
        render partial: "expenses/expense_card",
               locals: { expense: processed_expense, categories: categories }
      end

      it "hides the status badge for processed expenses" do
        expect(rendered).not_to have_css('[data-testid="status-badge"]')
      end
    end

    context "when expense status is pending" do
      before do
        render partial: "expenses/expense_card",
               locals: { expense: pending_expense, categories: categories }
      end

      it "shows the status badge for pending expenses" do
        expect(rendered).to have_css('[data-testid="status-badge"]')
      end

      it "shows the pending label text" do
        expect(rendered).to have_content("Pendiente")
      end
    end

    context "when expense status is duplicate" do
      let(:duplicate_expense) do
        create(:expense,
          merchant_name: "Store",
          amount: 1000.00,
          transaction_date: Date.new(2026, 3, 10),
          status: "duplicate",
          category: category)
      end

      before do
        render partial: "expenses/expense_card",
               locals: { expense: duplicate_expense, categories: categories }
      end

      it "shows the status badge for duplicate expenses" do
        expect(rendered).to have_css('[data-testid="status-badge"]')
      end
    end
  end

  describe "Stimulus data attributes" do
    before do
      render partial: "expenses/expense_card",
             locals: { expense: processed_expense, categories: categories }
    end

    it "has data-controller set to mobile-card" do
      expect(rendered).to have_css('[data-controller="mobile-card"]')
    end

    it "has card target attribute" do
      expect(rendered).to have_css('[data-mobile-card-target~="card"]')
    end

    it "has hidden actions container with actions target" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]')
    end

    it "has checkbox target" do
      expect(rendered).to have_css('[data-mobile-card-target="checkbox"]')
    end

    it "has expense id value attribute" do
      expect(rendered).to have_css("[data-mobile-card-expense-id-value='#{processed_expense.id}']")
    end

    it "has selection-mode-value attribute defaulting to false" do
      expect(rendered).to have_css("[data-mobile-card-selection-mode-value='false']")
    end

    it "has touch and click action attributes" do
      expect(rendered).to have_css(
        '[data-action*="click->mobile-card#toggleActions"]'
      )
      expect(rendered).to have_css(
        '[data-action*="touchstart->mobile-card#touchStart"]'
      )
      expect(rendered).to have_css(
        '[data-action*="touchend->mobile-card#touchEnd"]'
      )
    end
  end

  describe "accessibility" do
    before do
      render partial: "expenses/expense_card",
             locals: { expense: processed_expense, categories: categories }
    end

    it "has role=article on the card element" do
      expect(rendered).to have_css('[role="article"]')
    end

    it "has an aria-label containing merchant and amount" do
      expect(rendered).to have_css('[aria-label*="Super Mas"]')
    end
  end

  describe "actions container" do
    before do
      render partial: "expenses/expense_card",
             locals: { expense: processed_expense, categories: categories }
    end

    it "renders the actions section hidden by default" do
      # Actions div must be hidden via CSS class (hidden)
      expect(rendered).to have_css('[data-mobile-card-target="actions"].hidden')
    end

    it "renders a Categoría action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Categoría/)
    end

    it "renders an Estado action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Estado/)
    end

    it "renders an Editar action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Editar/)
    end

    it "renders an Eliminar action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Eliminar/)
    end
  end

  describe "category color dot" do
    context "when expense has a category" do
      before do
        render partial: "expenses/expense_card",
               locals: { expense: processed_expense, categories: categories }
      end

      it "renders a color dot with category color" do
        expect(rendered).to have_css('[style*="#FF6B6B"]')
      end
    end

    context "when expense has no category" do
      let(:uncategorized_expense) do
        create(:expense,
          merchant_name: "Unknown Store",
          amount: 500.00,
          transaction_date: Date.new(2026, 3, 10),
          status: "pending",
          category: nil)
      end

      before do
        render partial: "expenses/expense_card",
               locals: { expense: uncategorized_expense, categories: categories }
      end

      it "renders a fallback color dot" do
        expect(rendered).to have_css(".rounded-full")
      end
    end
  end

  describe "batch selection checkbox" do
    before do
      render partial: "expenses/expense_card",
             locals: { expense: processed_expense, categories: categories }
    end

    it "renders the checkbox hidden by default" do
      expect(rendered).to have_css('[data-mobile-card-target="checkbox"].hidden', visible: :all)
    end

    it "renders a checkbox input" do
      expect(rendered).to have_css('input[type="checkbox"]', visible: :all)
    end
  end
end
