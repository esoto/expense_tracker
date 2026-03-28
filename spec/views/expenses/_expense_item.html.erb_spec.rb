require "rails_helper"

# Spec for the unified responsive expense item partial.
# This partial replaces both _expense_card (mobile) and _expense_row (desktop),
# reducing 100 partial renders (50×2) to 50 per page load.
RSpec.describe "expenses/_expense_item.html.erb", type: :view, unit: true do
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
  let(:uncategorized_expense) do
    create(:expense,
      merchant_name: "Unknown Store",
      amount: 500.00,
      transaction_date: Date.new(2026, 3, 10),
      status: "pending",
      category: nil)
  end
  let(:categories) { [ category ] }

  def render_item(expense, cats = categories)
    render partial: "expenses/expense_item",
           locals: { expense: expense, categories: cats }
  end

  # ───────────────────────────────────────────────────────
  # Core data rendering (same data visible on both layouts)
  # ───────────────────────────────────────────────────────
  describe "merchant name display" do
    before { render_item(processed_expense) }

    it "renders the merchant name" do
      expect(rendered).to have_content("Super Mas")
    end

    it "renders the formatted amount" do
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

  describe "missing merchant name" do
    let(:no_merchant_expense) do
      create(:expense,
        merchant_name: nil,
        amount: 1000.00,
        transaction_date: Date.new(2026, 3, 10),
        status: "pending",
        category: category)
    end

    before { render_item(no_merchant_expense) }

    it "shows a fallback italic text for missing merchant" do
      # Both mobile and desktop layouts show a fallback for nil merchant
      expect(rendered).to have_css("span.italic")
    end
  end

  # ───────────────────────────────────────────────────────
  # Status badge
  # ───────────────────────────────────────────────────────
  describe "status badge" do
    context "when expense status is processed" do
      before { render_item(processed_expense) }

      it "hides the status badge for processed expenses" do
        expect(rendered).not_to have_css('[data-testid="status-badge"]')
      end
    end

    context "when expense status is pending" do
      before { render_item(pending_expense) }

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

      before { render_item(duplicate_expense) }

      it "shows the status badge for duplicate expenses" do
        expect(rendered).to have_css('[data-testid="status-badge"]')
      end
    end
  end

  # ───────────────────────────────────────────────────────
  # Backward-compatible element IDs (Turbo Stream + JS)
  # ───────────────────────────────────────────────────────
  describe "element IDs" do
    before { render_item(processed_expense) }

    it "uses expense_row_ prefix for the item ID (backward compat with destroy.turbo_stream)" do
      expect(rendered).to have_css("#expense_row_#{processed_expense.id}")
    end

    it "has data-expense-item attribute on the root element" do
      expect(rendered).to have_css("[data-expense-item]")
    end
  end

  # ───────────────────────────────────────────────────────
  # Stimulus controllers
  # ───────────────────────────────────────────────────────
  describe "Stimulus data attributes" do
    before { render_item(processed_expense) }

    it "includes the inline-actions controller" do
      expect(rendered).to have_css('[data-controller*="inline-actions"]')
    end

    it "includes the mobile-card controller" do
      expect(rendered).to have_css('[data-controller*="mobile-card"]')
    end

    it "has inline-actions expense-id-value set" do
      expect(rendered).to have_css("[data-inline-actions-expense-id-value='#{processed_expense.id}']")
    end

    it "has mobile-card expense-id-value set" do
      expect(rendered).to have_css("[data-mobile-card-expense-id-value='#{processed_expense.id}']")
    end

    it "is keyboard focusable with tabindex=0" do
      expect(rendered).to have_css('[tabindex="0"]')
    end

    it "has aria-selected=false by default" do
      expect(rendered).to have_css('[aria-selected="false"]')
    end

    it "has an aria-label containing merchant name" do
      expect(rendered).to have_css('[aria-label*="Super Mas"]')
    end
  end

  # ───────────────────────────────────────────────────────
  # Batch selection (desktop)
  # ───────────────────────────────────────────────────────
  describe "batch selection checkbox" do
    before { render_item(processed_expense) }

    it "has batch-selection-target='row' attribute" do
      expect(rendered).to have_css('[data-batch-selection-target="row"]')
    end

    it "has a desktop checkbox with batch-selection-target='checkbox'" do
      expect(rendered).to have_css('[data-batch-selection-target="checkbox"]', visible: :all)
    end

    it "has data-expense-id on the desktop checkbox" do
      expect(rendered).to have_css("[data-expense-id='#{processed_expense.id}']", visible: :all)
    end
  end

  # ───────────────────────────────────────────────────────
  # Mobile card layout
  # ───────────────────────────────────────────────────────
  describe "mobile card layout" do
    before { render_item(processed_expense) }

    it "renders mobile actions section hidden by default" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"].hidden', visible: :all)
    end

    it "has mobile Categorizar action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Categor/, visible: :all)
    end

    it "has mobile Estado action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Estado/, visible: :all)
    end

    it "has mobile Editar action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Editar/, visible: :all)
    end

    it "has mobile Eliminar action button" do
      expect(rendered).to have_css('[data-mobile-card-target="actions"]', text: /Eliminar/, visible: :all)
    end

    it "renders mobile category dropdown target hidden" do
      expect(rendered).to have_css('[data-mobile-card-target="categoryDropdown"]', visible: :all)
    end

    it "renders mobile checkbox hidden by default" do
      expect(rendered).to have_css('[data-mobile-card-target="checkbox"].hidden', visible: :all)
    end

    it "has touch and click action attributes" do
      expect(rendered).to have_css('[data-action*="touchstart->mobile-card#touchStart"]')
      expect(rendered).to have_css('[data-action*="touchend->mobile-card#touchEnd"]')
    end

    it "has keyboard action attributes for accessibility" do
      expect(rendered).to have_css('[data-action*="keydown.enter->mobile-card#toggleActions"]')
      expect(rendered).to have_css('[data-action*="keydown.escape->mobile-card#collapseActions"]')
    end
  end

  # ───────────────────────────────────────────────────────
  # Desktop row layout
  # ───────────────────────────────────────────────────────
  describe "desktop row layout" do
    before { render_item(processed_expense) }

    it "renders the inline-actions actionsContainer target" do
      expect(rendered).to have_css('[data-inline-actions-target="actionsContainer"]', visible: :all)
    end

    it "renders the category dropdown for desktop" do
      expect(rendered).to have_css('[data-inline-actions-target="categoryDropdown"]', visible: :all)
    end

    it "renders the delete confirmation modal" do
      expect(rendered).to have_css('[data-inline-actions-target="deleteConfirmation"]', visible: :all)
    end

    it "renders expandedColumns targets for view toggle" do
      expect(rendered).to have_css('[data-view-toggle-target="expandedColumns"]', visible: :all, minimum: 3)
    end

    it "has category options in the desktop dropdown" do
      expect(rendered).to have_css("[data-category-id='#{category.id}']", visible: :all)
    end

    it "has category name in the desktop dropdown" do
      expect(rendered).to have_css("[data-category-name='Alimentación']", visible: :all)
    end
  end

  # ───────────────────────────────────────────────────────
  # Category display (Turbo Frame)
  # ───────────────────────────────────────────────────────
  describe "Turbo Frame category update target" do
    context "when expense has a category" do
      before { render_item(processed_expense) }

      it "renders the category turbo-frame with the correct ID" do
        expect(rendered).to have_css("turbo-frame#expense_#{processed_expense.id}_category")
      end

      it "renders the mobile category name span for Turbo Stream updates" do
        expect(rendered).to have_css("#expense_#{processed_expense.id}_category", text: "Alimentación")
      end
    end

    context "when expense has no category" do
      before { render_item(uncategorized_expense) }

      it "renders a fallback category dot for mobile" do
        expect(rendered).to have_css(".rounded-full")
      end
    end
  end

  # ───────────────────────────────────────────────────────
  # Category color display
  # ───────────────────────────────────────────────────────
  describe "category color" do
    context "when expense has a category" do
      before { render_item(processed_expense) }

      it "renders color styling using the category color" do
        expect(rendered).to have_css('[style*="#FF6B6B"]')
      end
    end

    context "when expense has no category" do
      before { render_item(uncategorized_expense) }

      it "renders a fallback slate color dot" do
        expect(rendered).to have_css(".bg-slate-400")
      end
    end
  end

  # ───────────────────────────────────────────────────────
  # Bank name display (desktop)
  # ───────────────────────────────────────────────────────
  describe "bank name" do
    let(:bac_expense) do
      create(:expense,
        merchant_name: "BACstore",
        amount: 2000.00,
        transaction_date: Date.new(2026, 3, 1),
        status: "processed",
        category: category)
    end

    before do
      allow(bac_expense).to receive(:bank_name).and_return("BAC")
      render_item(bac_expense)
    end

    it "renders bank name with appropriate styling" do
      expect(rendered).to have_content("BAC")
    end
  end

  # ───────────────────────────────────────────────────────
  # Verify mobile-only checkbox is scoped correctly
  # ───────────────────────────────────────────────────────
  describe "category dropdown mobile" do
    before { render_item(processed_expense) }

    it "renders category options inside the mobile dropdown" do
      expect(rendered).to have_css(
        '[data-mobile-card-target="categoryDropdown"] [data-action*="selectCategory"]',
        visible: :all,
        minimum: 1
      )
    end
  end
end
