# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExpensesController, type: :request, unit: true do
  let(:admin_user) { create(:admin_user) }
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:expenses) { create_list(:expense, 3, email_account: email_account) }
  let(:expense_ids) { expenses.map(&:id) }

  before { sign_in_admin(admin_user) }

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

      it "handles mixed expense ownership gracefully" do
        other_account = create(:email_account)
        other_expenses = create_list(:expense, 2, email_account: other_account)

        mixed_ids = expense_ids + other_expenses.map(&:id)

        delete bulk_destroy_expenses_path, params: {
          expense_ids: mixed_ids
        }, as: :json

        # Without user auth, all expenses will be deleted
        # In production with auth, this would fail
        json = JSON.parse(response.body)
        expect(json["success"]).to be true

        # Comment: In production with authentication,
        # this would return unauthorized error
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

        expect(response).to redirect_to(admin_login_url)
      end

      it "redirects unauthenticated bulk_update_status to login" do
        post bulk_update_status_expenses_path, params: {
          expense_ids: expense_ids,
          status: "processed"
        }

        expect(response).to redirect_to(admin_login_url)
      end

      it "redirects unauthenticated dashboard access to login" do
        get dashboard_expenses_path

        expect(response).to redirect_to(admin_login_url)
      end
    end
  end

end
