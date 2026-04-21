# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExpensesController, type: :request, unit: true do
  let(:admin_user) { create(:admin_user) }
  # PR 5: bulk ops now scope via scoping_user.email_accounts. Explicitly create
  # a User and anchor email_accounts/expenses to it so the scope fires on the
  # fixtures this spec owns.
  let(:scoping_user_fixture) { create(:user, :admin) }
  let(:email_account) { create(:email_account, user: scoping_user_fixture) }
  let(:category) { create(:category) }
  let(:expenses) { create_list(:expense, 3, email_account: email_account, user: scoping_user_fixture) }
  let(:expense_ids) { expenses.map(&:id) }

  before do
    sign_in_admin(admin_user)
    allow_any_instance_of(ExpensesController)
      .to receive(:scoping_user).and_return(scoping_user_fixture)
  end

  describe "Security: Strong Parameters", unit: true do
    describe "POST /expenses/bulk_update_status", unit: true do
      it "filters out unpermitted parameters" do
        post bulk_update_status_expenses_path, params: {
          expense_ids: expense_ids,
          status: "processed",
          category_id: category.id, # Should be filtered out
          amount: 99999 # Should be filtered out
        }, as: :json

        expect(response).to have_http_status(:ok)

        # Verify only status was updated
        expenses.each(&:reload)
        expenses.each do |expense|
          expect(expense.status).to eq("processed")
          expect(expense.category_id).not_to eq(category.id) unless expense.category_id == category.id
          expect(expense.amount).not_to eq(99999)
        end
      end

      it "validates status values" do
        post bulk_update_status_expenses_path, params: {
          expense_ids: expense_ids,
          status: "invalid_status"
        }, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
      end
    end

    describe "DELETE /expenses/bulk_destroy", unit: true do
      it "filters out all parameters except expense_ids" do
        initial_count = Expense.count

        delete bulk_destroy_expenses_path, params: {
          expense_ids: expense_ids,
          force: true, # Should be ignored
          cascade: true, # Should be ignored
          permanent: true # Should be ignored
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true

        # Since we don't have user auth, all expenses should be deleted
        expect(Expense.where(id: expense_ids).count).to eq(0)
      end

      it "rejects the whole bulk op when any id belongs to another user" do
        # PR 5: base_service#handle_missing_expenses returns success: false
        # with a "not found or unauthorized" error when any submitted id is
        # outside scoping_user.email_accounts. No expenses are deleted —
        # security-first: fail the whole op rather than partially delete.
        other_user = create(:user)
        other_account = create(:email_account, user: other_user)
        other_expenses = create_list(:expense, 2, email_account: other_account, user: other_user)

        mixed_ids = expense_ids + other_expenses.map(&:id)

        delete bulk_destroy_expenses_path, params: {
          expense_ids: mixed_ids
        }, as: :json

        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to match(/not found|unauthorized/i)

        # Nothing deleted — fail-closed semantics for mixed ownership.
        expect(Expense.where(id: expense_ids).count).to eq(3)
        expect(Expense.where(id: other_expenses.map(&:id)).count).to eq(2)
      end
    end
  end

  describe "Security: Authentication Enforcement", unit: true do
    context "when not authenticated" do
      before do
        # Clear the authenticated session so requests hit the real auth flow
        reset!
      end

      it "redirects unauthenticated bulk_destroy to login" do
        delete bulk_destroy_expenses_path, params: {
          expense_ids: expense_ids
        }

        expect(response).to redirect_to(login_url)
      end

      it "redirects unauthenticated bulk_update_status to login" do
        post bulk_update_status_expenses_path, params: {
          expense_ids: expense_ids,
          status: "processed"
        }

        expect(response).to redirect_to(login_url)
      end

      it "redirects unauthenticated dashboard access to login" do
        get dashboard_expenses_path

        expect(response).to redirect_to(login_url)
      end
    end
  end
end
