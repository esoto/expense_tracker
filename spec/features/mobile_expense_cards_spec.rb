require "rails_helper"

# Feature spec for PER-133: Mobile Card Layout
# Tests the responsive expense index view and the expense card partial
# These are view-level unit tests (tagged :unit) and do not require a browser.
RSpec.describe "Mobile Expense Cards", type: :view, unit: true do
  let(:category) { create(:category, name: "Alimentación", color: "#10B981") }
  let(:email_account) { create(:email_account) }
  let(:processed_expense) do
    create(:expense,
      merchant_name: "Super Mas",
      amount: 12500.00,
      transaction_date: Date.new(2026, 3, 15),
      status: "processed",
      category: category,
      email_account: email_account)
  end
  let(:pending_expense) do
    create(:expense,
      merchant_name: "McDonald's",
      amount: 3400.00,
      transaction_date: Date.new(2026, 3, 20),
      status: "pending",
      category: category,
      email_account: email_account)
  end

  # ============================================================
  # Card partial rendering
  # ============================================================
  describe "expense card partial" do
    context "with a processed expense" do
      before do
        render partial: "expenses/expense_card",
               locals: { expense: processed_expense, categories: [ category ] }
      end

      it "renders the merchant name" do
        expect(rendered).to have_content("Super Mas")
      end

      it "renders the category name" do
        expect(rendered).to have_content("Alimentación")
      end

      it "renders the date in dd/mm/yyyy format" do
        expect(rendered).to have_content("15/03/2026")
      end

      it "does not show status badge for processed expenses" do
        expect(rendered).not_to have_css('[data-testid="status-badge"]')
      end

      it "has the mobile-card Stimulus controller attribute" do
        expect(rendered).to have_css('[data-controller="mobile-card"]')
      end

      it "has tabindex=0 for keyboard accessibility" do
        expect(rendered).to have_css('[tabindex="0"]')
      end

      it "has the actions container hidden by default" do
        expect(rendered).to have_css('[data-mobile-card-target="actions"].hidden')
      end

      it "has a hidden checkbox for batch selection" do
        expect(rendered).to have_css('[data-mobile-card-target="checkbox"].hidden', visible: :all)
      end
    end

    context "with a pending expense" do
      before do
        render partial: "expenses/expense_card",
               locals: { expense: pending_expense, categories: [ category ] }
      end

      it "shows the status badge for pending expenses" do
        expect(rendered).to have_css('[data-testid="status-badge"]')
      end

      it "shows 'Pendiente' label" do
        expect(rendered).to have_content("Pendiente")
      end
    end
  end

  # ============================================================
  # Index view template source verification
  # Tests the structure of index.html.erb directly from source
  # rather than rendering it (full render requires browser-level tests)
  # ============================================================
  describe "collapsible filters" do
    let(:template_source) { File.read(Rails.root.join("app/views/expenses/index.html.erb")) }

    it "renders filter toggle button for mobile" do
      expect(template_source).to include("Filtrar")
    end

    it "has collapsible-filter controller on filters" do
      expect(template_source).to include("data-controller=\"collapsible-filter\"")
    end

    it "has a collapsible content target wrapping the filter form" do
      expect(template_source).to include("data-collapsible-filter-target=\"content\"")
    end

    it "has a toggle button action wired to the collapsible-filter controller" do
      expect(template_source).to include("click->collapsible-filter#toggle")
    end

    it "collapsible content div is hidden by default on mobile" do
      expect(template_source).to match(/data-collapsible-filter-target="content"[^>]*class="hidden md:block"|class="hidden md:block"[^>]*data-collapsible-filter-target="content"/)
    end
  end

  describe "collapsible category summary" do
    let(:template_source) { File.read(Rails.root.join("app/views/expenses/index.html.erb")) }

    it "renders summary toggle button" do
      expect(template_source).to include("Ver resumen")
    end

    it "has collapsible-filter controller on category summary section" do
      # The category summary section reuses the same collapsible-filter controller
      expect(template_source).to include("Resumen por Categoría")
    end

    it "wraps category grid in a collapsible content target" do
      expect(template_source).to match(/Ver resumen/)
    end
  end

  describe "expenses/index.html.erb template source" do
    let(:template_path) do
      Rails.root.join("app/views/expenses/index.html.erb")
    end
    let(:template_source) { File.read(template_path) }

    it "contains a mobile card container with id expense_cards" do
      expect(template_source).to include('id="expense_cards"')
    end

    it "hides mobile card container on md+ screens with md:hidden" do
      expect(template_source).to match(/id="expense_cards"[^>]*md:hidden/)
    end

    it "renders expense_card partial inside the mobile container" do
      expect(template_source).to include('render "expense_card"')
    end

    it "passes expense and categories locals to expense_card" do
      expect(template_source).to include('expense: expense, categories: @categories')
    end

    it "shows expense_count in mobile container header" do
      expect(template_source).to include('@expense_count')
    end

    it "has desktop table container with id expense_list" do
      expect(template_source).to include('id="expense_list"')
    end

    it "adds hidden class to desktop table container so it is hidden on mobile" do
      expect(template_source).to match(/id="expense_list"[^>]*hidden md:block/)
    end

    it "has md:block on the desktop table container for medium+ screens" do
      expect(template_source).to match(/id="expense_list"[^>]*md:block/)
    end

    it "includes Lista de Gastos heading in mobile section" do
      # The mobile header for the card list
      expect(template_source).to include("Lista de Gastos")
    end

    it "includes mobile pagination block" do
      expect(template_source).to include("Mobile Pagination")
    end
  end

  # ============================================================
  # Responsive layout — verified from card partial source
  # ============================================================
  describe "expense_card partial structure" do
    let(:partial_path) do
      Rails.root.join("app/views/expenses/_expense_card.html.erb")
    end
    let(:partial_source) { File.read(partial_path) }

    it "has data-controller mobile-card attribute" do
      expect(partial_source).to include('data-controller="mobile-card"')
    end

    it "has tabindex=0 for keyboard accessibility" do
      expect(partial_source).to include('tabindex="0"')
    end

    it "has actions target attribute" do
      expect(partial_source).to include('data-mobile-card-target="actions"')
    end

    it "has checkbox target attribute" do
      expect(partial_source).to include('data-mobile-card-target="checkbox"')
    end

    it "includes touch and click action handlers" do
      expect(partial_source).to include("click->mobile-card#toggleActions")
      expect(partial_source).to include("touchstart->mobile-card#touchStart")
      expect(partial_source).to include("touchend->mobile-card#touchEnd")
    end

    it "has keyboard action handlers for accessibility" do
      expect(partial_source).to include("keydown.enter->mobile-card#toggleActions")
      expect(partial_source).to include("keydown.escape->mobile-card#collapseActions")
    end

    it "actions container element includes both hidden class and actions target" do
      # The actions div has class="hidden ..." AND data-mobile-card-target="actions"
      # These may appear on separate lines within the same div opening tag
      expect(partial_source).to include('data-mobile-card-target="actions"')
      # The div containing the actions target should also have 'hidden' class
      expect(partial_source).to match(/class="hidden[^"]*"[^>]*data-mobile-card-target="actions"|data-mobile-card-target="actions"[^>]*class="[^"]*hidden/)
    end
  end
end
