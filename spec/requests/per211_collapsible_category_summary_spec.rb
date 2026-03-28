require "rails_helper"

# Request spec for PER-211: "Ver resumen" collapsible toggle for category summary on mobile.
# Verifies that the expenses index page renders the collapsible structure with the correct
# Stimulus controller attributes so the JavaScript toggle can function on mobile (375px).
RSpec.describe "PER-211: Collapsible Category Summary", type: :request, unit: true do
  let!(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account) }
  let!(:category) { create(:category, name: "Alimentación", color: "#10B981") }
  let!(:expense) do
    create(:expense,
      email_account: email_account,
      category: category,
      amount: 15_000,
      transaction_date: Date.current,
      status: "processed")
  end

  before { sign_in_admin(admin_user) }

  describe "GET /expenses" do
    before { get expenses_path }

    it "returns a successful response" do
      expect(response).to have_http_status(:ok)
    end

    context "collapsible category summary section" do
      it "renders the category summary container with collapsible controller" do
        expect(response.body).to include('data-controller="collapsible"')
      end

      it "renders the Ver resumen button with toggleButton target" do
        expect(response.body).to include('data-collapsible-target="toggleButton"')
      end

      it "renders the Ver resumen button with the toggle action" do
        expect(response.body).to include('data-action="click->collapsible#toggle"')
      end

      it "renders the Ver resumen button with aria-expanded set to false initially" do
        expect(response.body).to include('aria-expanded="false"')
      end

      it "renders the Ver resumen label text" do
        expect(response.body).to include("Ver resumen")
      end

      it "renders the content target element" do
        expect(response.body).to include('data-collapsible-target="content"')
      end

      it "renders the content target with hidden class for mobile-first collapsed state" do
        # Content must start hidden on mobile; md:block makes it visible on desktop
        expect(response.body).to match(/data-collapsible-target="content"[^>]*class="[^"]*hidden[^"]*md:block/)
      end

      it "renders the Resumen por Categoría heading inside the collapsible block" do
        expect(response.body).to include("Resumen por Categoría")
      end

      it "renders category names in the summary grid" do
        expect(response.body).to include("Alimentación")
      end

      it "renders the toggle button with collapsible label span for dynamic text" do
        expect(response.body).to include("data-collapsible-label")
      end

      it "renders closed label attribute for 'Ver resumen' state" do
        expect(response.body).to include('data-collapsible-label-closed="Ver resumen"')
      end

      it "renders open label attribute for 'Ocultar resumen' state" do
        expect(response.body).to include('data-collapsible-label-open="Ocultar resumen"')
      end
    end

    context "collapsible filters section" do
      it "renders the filter toggle button with toggleButton target" do
        expect(response.body).to include('data-collapsible-target="toggleButton"')
      end

      it "renders the Filtrar button text" do
        expect(response.body).to include("Filtrar")
      end
    end
  end

  describe "GET /expenses with category filter applied" do
    it "does not render the category summary collapsible section when filtered by category" do
      get expenses_path, params: { category: category.name }

      expect(response).to have_http_status(:ok)
      # Category summary only renders when no category filter is applied
      expect(response.body).not_to include("Resumen por Categoría")
    end
  end

  describe "GET /expenses with no expenses" do
    before do
      Expense.destroy_all
      get expenses_path
    end

    it "does not render the category summary section when there are no expenses" do
      expect(response).to have_http_status(:ok)
      # @categories_summary.any? must be false — no collapsible summary rendered
      expect(response.body).not_to include("Resumen por Categoría")
    end
  end
end
