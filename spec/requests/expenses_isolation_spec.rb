# frozen_string_literal: true

require "rails_helper"

# Data-isolation contract for ExpensesController.
#
# This spec verifies that GET /expenses returns ONLY the expenses belonging to
# the scoping user and NEVER leaks another user's expenses.
#
# UserAuthentication is not yet gating ExpensesController (PR 12 does that).
# Until then the controller falls back to User.admin.first via `scoping_user`.
# This spec exercises that fallback path so the isolation contract is validated
# NOW and remains green when PR 12 wires up full auth.
#
# Pattern mirrors PR 4's email_accounts_isolation_spec.rb.
RSpec.describe "Expenses data isolation", type: :request, unit: true do
  # Bypass AdminUser-based authentication so we can control which User is
  # the scoping_user via the controller's fallback logic.
  before do
    allow_any_instance_of(ExpensesController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(ExpensesController).to receive(:current_user).and_return(nil)
  end

  describe "GET /expenses" do
    context "when scoping_user is User.admin.first (admin fallback path)" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }

      let!(:account_a) { create(:email_account, user: user_a) }
      let!(:account_b) { create(:email_account, user: user_b) }
      let!(:expense_a1) { create(:expense, user: user_a, email_account: account_a, merchant_name: "UserA Merchant One") }
      let!(:expense_a2) { create(:expense, user: user_a, email_account: account_a, merchant_name: "UserA Merchant Two") }
      let!(:expense_b)  { create(:expense, user: user_b, email_account: account_b, merchant_name: "UserB Exclusive Merchant") }

      before do
        # Stub scoping_user on the controller instance to return user_a,
        # simulating the case where user_a is the authenticated admin.
        allow_any_instance_of(ExpensesController)
          .to receive(:scoping_user)
          .and_return(user_a)

        get expenses_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "includes user A's two expenses in the response" do
        expect(response.body).to include("UserA Merchant One")
        expect(response.body).to include("UserA Merchant Two")
      end

      it "does NOT include user B's expense in the response" do
        expect(response.body).not_to include("UserB Exclusive Merchant")
      end
    end

    context "scoping_user isolation — user B cannot see user A's expenses" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }

      let!(:account_a) { create(:email_account, user: user_a) }
      let!(:account_b) { create(:email_account, user: user_b) }
      let!(:expense_a) { create(:expense, user: user_a, email_account: account_a, merchant_name: "UserA Merchant") }
      let!(:expense_b) { create(:expense, user: user_b, email_account: account_b, merchant_name: "UserB Merchant") }

      before do
        allow_any_instance_of(ExpensesController)
          .to receive(:scoping_user)
          .and_return(user_b)

        get expenses_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end

      it "includes user B's expense" do
        expect(response.body).to include("UserB Merchant")
      end

      it "does NOT include user A's expense" do
        expect(response.body).not_to include("UserA Merchant")
      end
    end
  end

  describe "GET /expenses/:id" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:expense_a) { create(:expense, user: user_a, email_account: account_a) }

    context "when scoping_user is user_b (cross-user access attempt)" do
      before do
        allow_any_instance_of(ExpensesController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "redirects with not_found flash — user B cannot access user A's expense" do
        # The scoped find via for_user(user_b).find(expense_a.id) cannot find
        # the record because expense_a belongs to user_a. The controller rescues
        # RecordNotFound and redirects with an alert.
        get expense_path(expense_a)
        expect(response).to redirect_to(expenses_path)
      end
    end

    context "when scoping_user is user_a (owner access)" do
      before do
        allow_any_instance_of(ExpensesController)
          .to receive(:scoping_user)
          .and_return(user_a)
      end

      it "returns HTTP 200 for owner" do
        get expense_path(expense_a)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # Mutation isolation — PATCH/PUT/DELETE must fail for cross-user access.
  # The `set_expense` before_action scopes via `for_user(scoping_user)`,
  # so the lookup fails before the action body ever runs. The controller
  # rescues RecordNotFound and redirects.
  describe "mutation isolation (PATCH/PUT/DELETE)" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:expense_a) { create(:expense, user: user_a, email_account: account_a, merchant_name: "OriginalMerchant") }

    context "when user_b tries to mutate user_a's expense" do
      before do
        allow_any_instance_of(ExpensesController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "PATCH redirects (not found) and does not mutate" do
        original_merchant = expense_a.merchant_name
        patch expense_path(expense_a),
          params: { expense: { merchant_name: "HijackedMerchant" } }
        expect(response).to redirect_to(expenses_path)
        expect(expense_a.reload.merchant_name).to eq(original_merchant)
      end

      it "PUT redirects (not found) and does not mutate" do
        original_merchant = expense_a.merchant_name
        put expense_path(expense_a),
          params: { expense: { merchant_name: "HijackedMerchant" } }
        expect(response).to redirect_to(expenses_path)
        expect(expense_a.reload.merchant_name).to eq(original_merchant)
      end

      it "DELETE redirects (not found) and does not destroy" do
        delete expense_path(expense_a)
        expect(response).to redirect_to(expenses_path)
        expect(Expense.exists?(expense_a.id)).to be true
      end
    end
  end

  # Create isolation — POSTed expenses are always assigned to scoping_user
  # regardless of any user_id passed in params.
  describe "POST /expenses — user_id cannot be spoofed via params" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }

    before do
      allow_any_instance_of(ExpensesController)
        .to receive(:scoping_user)
        .and_return(user_b)
    end

    it "assigns the new expense to scoping_user (user_b), ignoring a forged user_id param" do
      post expenses_path, params: {
        expense: {
          amount: 500.00,
          currency: "crc",
          transaction_date: Date.current.to_s,
          merchant_name: "IsolationTestMerchant",
          description: "Forged user_id test",
          user_id: user_a.id  # forged — strong params must drop this
        }
      }

      created = Expense.find_by(merchant_name: "IsolationTestMerchant")
      expect(created).not_to be_nil
      expect(created.user_id).to eq(user_b.id)
    end

    it "rejects a forged email_account_id pointing at another user's account" do
      account_a = create(:email_account, user: user_a)

      post expenses_path, params: {
        expense: {
          amount: 500.00,
          currency: "crc",
          transaction_date: Date.current.to_s,
          merchant_name: "ForgedAccountMerchant",
          description: "Forged email_account_id test",
          email_account_id: account_a.id  # forged — user_b cannot attach to user_a's account
        }
      }

      created = Expense.find_by(merchant_name: "ForgedAccountMerchant")
      # Either creation was rejected, or email_account_id was nullified
      # (depends on whether the rest of the params satisfied validations).
      expect(created&.email_account_id).not_to eq(account_a.id)
    end
  end

  # Owner forgery — a legitimate owner PATCHing with a forged email_account_id
  # must not be able to move the record onto another user's account.
  describe "PATCH /expenses/:id — owner cannot forge email_account_id to another user's account" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:account_a) { create(:email_account, user: user_a) }
    let!(:account_b) { create(:email_account, user: user_b) }
    let!(:expense_a) { create(:expense, user: user_a, email_account: account_a) }

    before do
      allow_any_instance_of(ExpensesController)
        .to receive(:scoping_user)
        .and_return(user_a)
    end

    it "strips the forged email_account_id so the record never lands on account_b" do
      patch expense_path(expense_a), params: {
        expense: { email_account_id: account_b.id }
      }
      # Critical invariant: the expense must NOT end up on user_b's account.
      # Either the forged value was dropped (ending as nil) or held at account_a;
      # both outcomes satisfy the isolation contract.
      expect(expense_a.reload.email_account_id).not_to eq(account_b.id)
    end
  end
end
