# frozen_string_literal: true

require "rails_helper"

# PER-419: Verify expenses index works standalone with full widget
#
# The dashboard v2 redesign moved expense management features (filters, batch actions,
# virtual scrolling) out of the dashboard. This spec verifies that the expenses index
# page (/expenses) renders all required Stimulus controllers and HTML elements
# independently, without relying on any dashboard-specific DOM elements.
RSpec.describe "PER-419: Expenses index standalone verification", type: :request, unit: true do
  let!(:admin_user) { create(:admin_user) }
  let!(:email_account) { create(:email_account) }
  let!(:category) { create(:category, name: "Alimentación", color: "#10B981") }
  let!(:expense) do
    create(:expense,
      email_account: email_account,
      category: category,
      amount: 25_000,
      transaction_date: Date.current,
      status: "processed")
  end

  before { sign_in_admin(admin_user) }

  describe "GET /expenses renders successfully" do
    before { get expenses_path }

    it "returns HTTP 200" do
      expect(response).to have_http_status(:ok)
    end

    it "renders the expenses index heading" do
      expect(response.body).to include("Gastos")
    end

    it "renders expense data in the response body" do
      # Spanish locale uses period as thousands delimiter
      expect(response.body).to include("25.000")
    end
  end

  describe "Stimulus controller data attributes are present" do
    before { get expenses_path }

    it "renders the filter-chips controller" do
      expect(response.body).to include('data-controller="filter-chips"')
    end

    it "renders the filter-persistence controller" do
      expect(response.body).to include('data-controller="filter-persistence"')
    end

    it "renders the virtual-scroll controller on the expense list" do
      expect(response.body).to include("virtual-scroll")
    end

    it "renders the batch-selection controller on the expense list" do
      expect(response.body).to include("batch-selection")
    end

    it "renders the view-toggle controller on the expense list" do
      expect(response.body).to include("view-toggle")
    end

    it "renders the accessibility-enhanced controller" do
      expect(response.body).to include('data-controller="accessibility-enhanced"')
    end

    it "renders the inline-actions controller on expense items (not dashboard-inline-actions)" do
      expect(response.body).to include('data-controller="inline-actions mobile-card"')
    end

    it "does not reference dashboard-expenses controller" do
      expect(response.body).not_to include('data-controller="dashboard-expenses')
    end

    it "does not reference dashboard-inline-actions controller" do
      expect(response.body).not_to include('data-controller="dashboard-inline-actions')
    end

    it "does not reference dashboard-filter-chips controller" do
      expect(response.body).not_to include('data-controller="dashboard-filter-chips')
    end
  end

  describe "filter-related HTML elements are present" do
    before { get expenses_path }

    it "renders the filter form with category select" do
      expect(response.body).to include("Alimentación")
    end

    it "renders the filter submit button" do
      expect(response.body).to include("Filtrar")
    end

    it "renders the clear filters link" do
      expect(response.body).to include(expenses_path)
    end

    it "renders the start_date input" do
      expect(response.body).to include("start_date")
    end

    it "renders the end_date input" do
      expect(response.body).to include("end_date")
    end

    it "renders filter-persistence targets on the form" do
      expect(response.body).to include('data-filter-persistence-target="filterForm"')
    end

    it "renders filter-persistence targets on filter inputs" do
      expect(response.body).to include('data-filter-persistence-target="filterInput"')
    end

    it "renders the filter-chips container with base URL" do
      expect(response.body).to include('data-filter-chips-base-url-value="/expenses"')
    end

    it "renders the filter-persistence storage type value" do
      expect(response.body).to include('data-filter-persistence-storage-type-value="session"')
    end

    it "renders the filter-persistence auto-restore value" do
      expect(response.body).to include('data-filter-persistence-auto-restore-value="true"')
    end
  end

  describe "page works without dashboard-specific elements" do
    before { get expenses_path }

    it "does not render the dashboard sync widget" do
      expect(response.body).not_to include("Sincronización de Correos")
    end

    it "does not render dashboard metric cards" do
      expect(response.body).not_to include("Dashboard de Gastos")
    end

    it "does not render the dashboard navigation breadcrumb when not from dashboard" do
      expect(response.body).not_to include("Volver al Dashboard")
    end

    it "renders standalone summary stats" do
      expect(response.body).to include("Total")
    end

    it "renders the category count stat" do
      expect(response.body).to include("Categorías")
    end

    it "renders the collapsible filter section for mobile" do
      expect(response.body).to include('data-controller="collapsible"')
    end
  end

  describe "batch actions toolbar markup is present" do
    before { get expenses_path }

    it "renders the batch selection toolbar container" do
      expect(response.body).to include('data-batch-selection-target="selectionToolbar"')
    end

    it "renders the selection counter element" do
      expect(response.body).to include('data-batch-selection-target="selectionCounter"')
    end

    it "renders the master checkbox for select-all" do
      expect(response.body).to include('data-batch-selection-target="masterCheckbox"')
    end

    it "renders the master checkbox toggle action" do
      expect(response.body).to include('data-action="change->batch-selection#toggleMasterSelection"')
    end

    it "renders the selection mode toggle button" do
      expect(response.body).to include("click->batch-selection#toggleSelectionMode")
    end

    it "renders the clear selection button" do
      expect(response.body).to include('data-batch-selection-target="clearSelectionButton"')
    end

    it "renders the bulk actions button" do
      expect(response.body).to include('data-batch-selection-target="bulkActionsButton"')
    end

    it "renders the bulk operations modal partial" do
      expect(response.body).to include("bulk-operations")
    end

    it "renders the selected count display" do
      expect(response.body).to include('data-batch-selection-target="selectedCount"')
    end

    it "renders the total count display" do
      expect(response.body).to include('data-batch-selection-target="totalCount"')
    end
  end

  describe "virtual scroll attributes are present" do
    before { get expenses_path }

    it "renders the virtual-scroll threshold value" do
      expect(response.body).to include("data-virtual-scroll-threshold-value")
    end

    it "renders the virtual-scroll enabled value" do
      expect(response.body).to include("data-virtual-scroll-enabled-value")
    end
  end

  describe "view toggle elements are present" do
    before { get expenses_path }

    it "renders the toggle button" do
      expect(response.body).to include('data-view-toggle-target="toggleButton"')
    end

    it "renders the compact icon target" do
      expect(response.body).to include('data-view-toggle-target="compactIcon"')
    end

    it "renders the expanded icon target" do
      expect(response.body).to include('data-view-toggle-target="expandedIcon"')
    end

    it "renders the button text target" do
      expect(response.body).to include('data-view-toggle-target="buttonText"')
    end

    it "renders the item list target" do
      expect(response.body).to include('data-view-toggle-target="itemList"')
    end

    it "renders the expanded columns targets for desktop headers" do
      expect(response.body).to include('data-view-toggle-target="expandedColumns"')
    end
  end

  describe "inline actions on expense items" do
    before { get expenses_path }

    it "renders inline-actions expense-id value on expense rows" do
      expect(response.body).to include("data-inline-actions-expense-id-value=\"#{expense.id}\"")
    end

    it "renders inline-actions current-status value on expense rows" do
      expect(response.body).to include('data-inline-actions-current-status-value="processed"')
    end

    it "renders the category dropdown toggle action" do
      expect(response.body).to include("click->inline-actions#toggleCategoryDropdown")
    end

    it "renders the status toggle action" do
      expect(response.body).to include("click->inline-actions#toggleStatus")
    end

    it "renders the duplicate action" do
      expect(response.body).to include("click->inline-actions#duplicateExpense")
    end

    it "renders the delete confirmation action" do
      expect(response.body).to include("click->inline-actions#showDeleteConfirmation")
    end

    it "renders the category dropdown target" do
      expect(response.body).to include('data-inline-actions-target="categoryDropdown"')
    end

    it "renders the delete confirmation target" do
      expect(response.body).to include('data-inline-actions-target="deleteConfirmation"')
    end
  end

  describe "GET /expenses with filters applied" do
    it "renders successfully with category filter" do
      get expenses_path, params: { category: "Alimentación" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alimentación")
    end

    it "renders successfully with date range filter" do
      get expenses_path, params: {
        start_date: Date.current.beginning_of_month.to_s,
        end_date: Date.current.to_s
      }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /expenses with no expenses" do
    before do
      Expense.destroy_all
      get expenses_path
    end

    it "returns HTTP 200 even with no expenses" do
      expect(response).to have_http_status(:ok)
    end

    it "still renders the core Stimulus controllers" do
      expect(response.body).to include('data-controller="filter-chips"')
      expect(response.body).to include('data-controller="filter-persistence"')
    end

    it "still renders filter elements" do
      expect(response.body).to include("start_date")
      expect(response.body).to include("end_date")
    end
  end
end
