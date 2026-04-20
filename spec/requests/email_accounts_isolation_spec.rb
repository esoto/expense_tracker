# frozen_string_literal: true

require "rails_helper"

# Data-isolation contract for EmailAccountsController.
#
# This spec verifies that GET /email_accounts returns ONLY the accounts
# belonging to the scoping user and NEVER leaks another user's accounts.
#
# UserAuthentication is not yet gating EmailAccountsController (PR 12 does
# that).  Until then the controller falls back to User.admin.first via
# `scoping_user`.  This spec exercises that fallback path so the isolation
# contract is validated NOW and remains green when PR 12 wires up full auth.
#
# PRs 5-10 replicate this pattern for their respective models.
RSpec.describe "EmailAccounts data isolation", type: :request, unit: true do
  # Bypass AdminUser-based authentication so we can control which User is
  # the scoping_user via the controller's fallback logic.
  before do
    allow_any_instance_of(EmailAccountsController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(EmailAccountsController).to receive(:current_user).and_return(nil)
  end

  describe "GET /email_accounts" do
    context "when scoping_user is User.admin.first (admin fallback path)" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }

      let!(:account_a1) { create(:email_account, user: user_a) }
      let!(:account_a2) { create(:email_account, user: user_a) }
      let!(:account_b)  { create(:email_account, user: user_b) }

      before do
        # Stub scoping_user on the controller instance to return user_a,
        # simulating the case where user_a is the authenticated admin.
        allow_any_instance_of(EmailAccountsController)
          .to receive(:scoping_user)
          .and_return(user_a)

        get email_accounts_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "includes user A's two accounts in the response" do
        expect(response.body).to include(account_a1.email)
        expect(response.body).to include(account_a2.email)
      end

      it "does NOT include user B's account in the response" do
        expect(response.body).not_to include(account_b.email)
      end
    end

    context "scoping_user isolation — user B cannot see user A's accounts" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }

      let!(:account_a) { create(:email_account, user: user_a) }
      let!(:account_b) { create(:email_account, user: user_b) }

      before do
        allow_any_instance_of(EmailAccountsController)
          .to receive(:scoping_user)
          .and_return(user_b)

        get email_accounts_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "includes user B's account" do
        expect(response.body).to include(account_b.email)
      end

      it "does NOT include user A's account" do
        expect(response.body).not_to include(account_a.email)
      end
    end
  end

  describe "GET /email_accounts/:id" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }

    context "when scoping_user is user_b (cross-user access attempt)" do
      before do
        allow_any_instance_of(EmailAccountsController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "returns 404 — user B cannot access user A's account" do
        # Rails catches RecordNotFound and renders a 404 in request specs.
        # The scoped find via for_user(user_b).find(account_a.id) cannot find
        # the record because account_a belongs to user_a.
        get email_account_path(account_a)
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when scoping_user is user_a (owner access)" do
      before do
        allow_any_instance_of(EmailAccountsController)
          .to receive(:scoping_user)
          .and_return(user_a)
      end

      it "returns HTTP 200 for owner" do
        get email_account_path(account_a)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # Mutation isolation — PATCH/PUT/DELETE must 404 for cross-user access.
  # The `set_email_account` before_action scopes via `for_user(scoping_user)`,
  # so the lookup fails before the action body ever runs. This contract MUST
  # be proven at the request level (not just trusted from the code) because
  # PRs 5-10 copy this template and silent regressions would propagate.
  describe "mutation isolation (PATCH/PUT/DELETE)" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }

    context "when user_b tries to mutate user_a's account" do
      before do
        allow_any_instance_of(EmailAccountsController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "PATCH returns 404 and does not mutate" do
        original_email = account_a.email
        patch email_account_path(account_a),
          params: { email_account: { email: "hijacked@example.com" } }
        expect(response).to have_http_status(:not_found)
        expect(account_a.reload.email).to eq(original_email)
      end

      it "PUT returns 404 and does not mutate" do
        original_email = account_a.email
        put email_account_path(account_a),
          params: { email_account: { email: "hijacked@example.com" } }
        expect(response).to have_http_status(:not_found)
        expect(account_a.reload.email).to eq(original_email)
      end

      it "DELETE returns 404 and does not destroy" do
        delete email_account_path(account_a)
        expect(response).to have_http_status(:not_found)
        expect(EmailAccount.exists?(account_a.id)).to be true
      end
    end
  end

  # Create isolation — POSTed email_accounts are always assigned to
  # scoping_user regardless of any user_id passed in params.
  describe "POST /email_accounts — user_id cannot be spoofed via params" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }

    before do
      allow_any_instance_of(EmailAccountsController)
        .to receive(:scoping_user)
        .and_return(user_b)
    end

    it "assigns the new account to scoping_user (user_b), ignoring a forged user_id param" do
      post email_accounts_path, params: {
        email_account: {
          email: "new@example.com",
          provider: "gmail",
          bank_name: "BAC",
          user_id: user_a.id  # forged — strong params must drop this
        }
      }

      created = EmailAccount.find_by(email: "new@example.com")
      expect(created).not_to be_nil
      expect(created.user_id).to eq(user_b.id)
    end
  end
end
