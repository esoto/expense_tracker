# frozen_string_literal: true

require "rails_helper"

# PER-174: Prevent admin Stimulus controllers from polluting non-admin pages
# via Turbo Drive navigation.
#
# Root cause: When navigating admin → budgets via Turbo Drive, Stimulus
# controllers from admin pages (e.g. pattern-form) stayed alive and
# intercepted actions on unrelated pages. The fix is to render admin pages
# with <meta name="turbo-visit-control" content="reload">, forcing a full
# page load when navigating away from admin, which disconnects all Stimulus
# controllers.
RSpec.describe "PER-174 Turbo Drive isolation", type: :request do
  let(:admin_user) { create(:admin_user) }
  let(:email_account) { create(:email_account) }

  before do
    allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
  end

  describe "GET /budgets/new", :unit do
    context "when authenticated as a regular user" do
      before do
        # Stub regular user authentication so the budgets controller works
        allow_any_instance_of(BudgetsController).to receive(:authenticate_user!).and_return(true)
        allow_any_instance_of(BudgetsController).to receive(:current_user).and_return(nil)
      end

      it "returns 200 OK and renders the budgets form" do
        get new_budget_path
        expect(response).to have_http_status(:ok)
      end

      it "does NOT render the admin patterns form" do
        get new_budget_path
        expect(response.body).not_to include("Nuevo Patrón de Categorización")
      end

      it "renders the budget form content" do
        get new_budget_path
        expect(response.body).to include("Nuevo Presupuesto")
      end

      it "does not include admin pattern-form Stimulus controller actions" do
        get new_budget_path
        expect(response.body).not_to include("pattern-form#updateValueHelp")
      end
    end
  end

  describe "Admin layout turbo-visit-control meta tag", :unit do
    context "when authenticated as admin" do
      before do
        post admin_login_path, params: {
          admin_user: { email: admin_user.email, password: "AdminPassword123!" }
        }
      end

      it "includes turbo-visit-control reload meta tag on admin patterns index" do
        get admin_patterns_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('name="turbo-visit-control"')
        expect(response.body).to include('content="reload"')
      end

      it "includes turbo-visit-control reload meta tag on admin patterns new" do
        get new_admin_pattern_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('name="turbo-visit-control"')
        expect(response.body).to include('content="reload"')
      end
    end
  end
end
