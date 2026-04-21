# frozen_string_literal: true

require "rails_helper"

# Data-isolation contract for BudgetsController.
#
# This spec verifies that GET /budgets returns ONLY the budgets belonging to
# the scoping user and NEVER leaks another user's budgets.
#
# UserAuthentication is not yet gating BudgetsController (PR 12 does that).
# Until then the controller falls back to User.admin.first via `scoping_user`.
# This spec exercises that fallback path so the isolation contract is validated
# NOW and remains green when PR 12 wires up full auth.
#
# Pattern mirrors PR 5's expenses_isolation_spec.rb.
RSpec.describe "Budgets data isolation", type: :request, unit: true do
  # Bypass session authentication so we can control which User is
  # the scoping_user via the controller's fallback logic.
  before do
    allow_any_instance_of(BudgetsController).to receive(:require_authentication).and_return(true)
    allow_any_instance_of(BudgetsController).to receive(:current_user).and_return(nil)
  end

  describe "GET /budgets" do
    context "when scoping_user is User.admin.first (admin fallback path)" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }

      let!(:account_a) { create(:email_account, user: user_a) }
      let!(:account_b) { create(:email_account, user: user_b) }
      let!(:budget_a1) { create(:budget, user: user_a, email_account: account_a, name: "UserA Budget One") }
      let!(:budget_a2) { create(:budget, user: user_a, email_account: account_a, name: "UserA Budget Two", period: "weekly") }
      let!(:budget_b)  { create(:budget, user: user_b, email_account: account_b, name: "UserB Exclusive Budget") }

      before do
        allow_any_instance_of(BudgetsController)
          .to receive(:scoping_user)
          .and_return(user_a)

        get budgets_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "includes user A's two budgets in the response" do
        expect(response.body).to include("UserA Budget One")
        expect(response.body).to include("UserA Budget Two")
      end

      it "does NOT include user B's budget in the response" do
        expect(response.body).not_to include("UserB Exclusive Budget")
      end
    end

    context "scoping_user isolation — user B cannot see user A's budgets" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }

      let!(:account_a) { create(:email_account, user: user_a) }
      let!(:account_b) { create(:email_account, user: user_b) }
      let!(:budget_a) { create(:budget, user: user_a, email_account: account_a, name: "UserA Budget") }
      let!(:budget_b) { create(:budget, user: user_b, email_account: account_b, name: "UserB Budget") }

      before do
        allow_any_instance_of(BudgetsController)
          .to receive(:scoping_user)
          .and_return(user_b)

        get budgets_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "includes user B's budget" do
        expect(response.body).to include("UserB Budget")
      end

      it "does NOT include user A's budget" do
        expect(response.body).not_to include("UserA Budget")
      end
    end
  end

  describe "GET /budgets/:id" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:budget_a) { create(:budget, user: user_a, email_account: account_a) }

    context "when scoping_user is user_b (cross-user access attempt)" do
      before do
        allow_any_instance_of(BudgetsController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "redirects with not_found flash — user B cannot access user A's budget" do
        # The scoped find via for_user(user_b).find(budget_a.id) cannot find
        # the record because budget_a belongs to user_a. The controller rescues
        # RecordNotFound and redirects with an alert.
        get budget_path(budget_a)
        expect(response).to redirect_to(budgets_path)
      end
    end

    context "when scoping_user is user_a (owner access)" do
      before do
        allow_any_instance_of(BudgetsController)
          .to receive(:scoping_user)
          .and_return(user_a)
      end

      it "returns HTTP 200 for owner" do
        get budget_path(budget_a)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # Mutation isolation — PATCH/PUT/DELETE must fail for cross-user access.
  # The `set_budget` before_action scopes via `for_user(scoping_user)`,
  # so the lookup fails before the action body ever runs. The controller
  # rescues RecordNotFound and redirects.
  describe "mutation isolation (PATCH/PUT/DELETE)" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:budget_a) { create(:budget, user: user_a, email_account: account_a, name: "OriginalName") }

    context "when user_b tries to mutate user_a's budget" do
      before do
        allow_any_instance_of(BudgetsController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "PATCH redirects (not found) and does not mutate" do
        original_name = budget_a.name
        patch budget_path(budget_a),
          params: { budget: { name: "HijackedName" } }
        expect(response).to redirect_to(budgets_path)
        expect(budget_a.reload.name).to eq(original_name)
      end

      it "PUT redirects (not found) and does not mutate" do
        original_name = budget_a.name
        put budget_path(budget_a),
          params: { budget: { name: "HijackedName" } }
        expect(response).to redirect_to(budgets_path)
        expect(budget_a.reload.name).to eq(original_name)
      end

      it "DELETE redirects (not found) and does not destroy" do
        delete budget_path(budget_a)
        expect(response).to redirect_to(budgets_path)
        expect(Budget.exists?(budget_a.id)).to be true
      end
    end
  end

  # Create isolation — POSTed budgets are always assigned to scoping_user
  # regardless of any user_id passed in params.
  describe "POST /budgets — user_id cannot be spoofed via params" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_b) { create(:email_account, user: user_b) }

    before do
      allow_any_instance_of(BudgetsController)
        .to receive(:scoping_user)
        .and_return(user_b)
    end

    it "assigns the new budget to scoping_user (user_b), ignoring a forged user_id param" do
      post budgets_path, params: {
        budget: {
          name: "IsolationTestBudget",
          amount: 500_000,
          period: "monthly",
          email_account_id: account_b.id,
          user_id: user_a.id  # forged — strong params must drop this
        }
      }

      created = Budget.find_by(name: "IsolationTestBudget")
      expect(created).not_to be_nil
      expect(created.user_id).to eq(user_b.id)
    end

    it "rejects a forged email_account_id pointing at another user's account" do
      account_a = create(:email_account, user: user_a)

      post budgets_path, params: {
        budget: {
          name: "ForgedAccountBudget",
          amount: 500_000,
          period: "monthly",
          email_account_id: account_a.id  # forged — user_b cannot attach to user_a's account
        }
      }

      created = Budget.find_by(name: "ForgedAccountBudget")
      # Either creation was rejected, or email_account_id was nullified.
      expect(created&.email_account_id).not_to eq(account_a.id)
    end
  end

  # Owner forgery — a legitimate owner PATCHing with a forged email_account_id
  # must not be able to move the record onto another user's account.
  describe "PATCH /budgets/:id — owner cannot forge email_account_id to another user's account" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:account_b) { create(:email_account, user: user_b) }
    let!(:budget_a) { create(:budget, user: user_a, email_account: account_a) }

    before do
      allow_any_instance_of(BudgetsController)
        .to receive(:scoping_user)
        .and_return(user_a)
    end

    it "strips the forged email_account_id so the record never lands on account_b" do
      patch budget_path(budget_a), params: {
        budget: { email_account_id: account_b.id }
      }
      # Critical invariant: the budget must NOT end up on user_b's account.
      expect(budget_a.reload.email_account_id).not_to eq(account_b.id)
    end
  end
end
