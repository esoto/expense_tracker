# frozen_string_literal: true

require "rails_helper"

# PER-190: Email accounts form must not be polluted by admin/patterns Stimulus
# controllers via Turbo Drive navigation.
#
# Root cause (shared with PER-174): navigating admin → non-admin pages via
# Turbo Drive kept admin Stimulus controllers (e.g. pattern-form) alive in
# memory, where they could intercept actions on unrelated pages such as the
# email accounts form.
#
# Fix (landed in PER-174 / PR #197): Admin::BaseController sets
# `layout "admin"`, and the admin layout includes
# `<meta name="turbo-visit-control" content="reload">`. This forces a full
# page reload when navigating away from any admin page, which disconnects all
# admin-scoped Stimulus controllers before the next page renders.
RSpec.describe "PER-190 Email accounts Turbo Drive isolation", type: :request do
  let(:admin_user) { create(:user, :admin) }

  describe "GET /email_accounts/new", :unit do
    context "when authenticated as a regular user" do
      before do
        allow_any_instance_of(EmailAccountsController).to receive(:require_authentication).and_return(true)
        allow_any_instance_of(EmailAccountsController).to receive(:current_user).and_return(nil)
      end

      it "returns 200 OK" do
        get new_email_account_path
        expect(response).to have_http_status(:ok)
      end

      it "renders the email account form, not admin patterns content" do
        get new_email_account_path
        expect(response.body).to include("Nueva Cuenta de Correo")
      end

      it "does NOT render admin pattern categorization form heading" do
        get new_email_account_path
        expect(response.body).not_to include("Nuevo Patrón de Categorización")
      end

      it "does not include admin pattern-form Stimulus controller actions" do
        get new_email_account_path
        expect(response.body).not_to include("pattern-form#updateValueHelp")
      end

      it "does not include the turbo-visit-control reload meta tag (non-admin page)" do
        get new_email_account_path
        expect(response.body).not_to include('name="turbo-visit-control"')
      end
    end
  end

  describe "Admin layout turbo-visit-control meta tag prevents pollution", :unit do
    context "when authenticated as admin and visiting admin/patterns" do
      before do
        post login_path, params: {
          email: admin_user.email, password: "TestPass123!"
        }
      end

      it "includes turbo-visit-control reload on admin patterns pages" do
        get admin_patterns_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('name="turbo-visit-control"')
        expect(response.body).to include('content="reload"')
      end

      it "does NOT include turbo-visit-control on email accounts new page (separate session)" do
        # Simulate a non-admin request to confirm the non-admin layout is used
        allow_any_instance_of(EmailAccountsController).to receive(:require_authentication).and_return(true)
        allow_any_instance_of(EmailAccountsController).to receive(:current_user).and_return(nil)

        get new_email_account_path
        expect(response.body).not_to include('content="reload"')
      end
    end
  end
end
