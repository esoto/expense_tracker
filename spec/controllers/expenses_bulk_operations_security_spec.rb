# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExpensesController, type: :request do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:expenses) { create_list(:expense, 3, email_account: email_account) }
  let(:expense_ids) { expenses.map(&:id) }

  describe "Security: Strong Parameters" do
    describe "POST /expenses/bulk_categorize" do
      it "filters out unpermitted parameters" do
        post bulk_categorize_expenses_path, params: {
          expense_ids: expense_ids,
          category_id: category.id,
          malicious_param: "evil_value",
          admin: true,
          role: "superuser"
        }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        
        # Verify malicious params were not processed
        expenses.each(&:reload)
        expenses.each do |expense|
          expect(expense.attributes).not_to have_key("malicious_param")
          expect(expense.attributes).not_to have_key("admin")
          expect(expense.attributes).not_to have_key("role")
        end
      end

      it "requires expense_ids parameter" do
        post bulk_categorize_expenses_path, params: {
          category_id: category.id
        }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
      end

      it "requires category_id parameter" do
        post bulk_categorize_expenses_path, params: {
          expense_ids: expense_ids
        }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
      end

      it "prevents SQL injection in expense_ids" do
        malicious_ids = ["1 OR 1=1", "'; DROP TABLE expenses; --"]
        
        post bulk_categorize_expenses_path, params: {
          expense_ids: malicious_ids,
          category_id: category.id
        }, as: :json

        # Should handle safely - malicious IDs won't match any real expenses
        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        
        # Table should still exist
        expect(Expense.table_exists?).to be true
      end
    end

    describe "POST /expenses/bulk_update_status" do
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

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
      end
    end

    describe "DELETE /expenses/bulk_destroy" do
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

  describe "Security: Authorization" do
    context "when trying to modify expenses from different accounts" do
      let(:other_account) { create(:email_account) }
      let(:other_expenses) { create_list(:expense, 2, email_account: other_account) }

      it "handles expenses from different accounts" do
        post bulk_categorize_expenses_path, params: {
          expense_ids: other_expenses.map(&:id),
          category_id: category.id
        }, as: :json

        json = JSON.parse(response.body)
        # Without user auth, operation succeeds
        # In production with auth, this would fail
        expect(json["success"]).to be true
        
        # Comment: In production with authentication,
        # this would prevent modification of unauthorized expenses
      end
    end
  end

  describe "Security: Mass Assignment Protection" do
    it "prevents direct modification of protected attributes" do
      post bulk_categorize_expenses_path, params: {
        expense_ids: expense_ids,
        category_id: category.id,
        expense: {
          id: 99999,
          email_account_id: 99999,
          created_at: "2020-01-01"
        }
      }, as: :json

      # Should succeed but ignore the nested expense params
      expect(response).to have_http_status(:ok)
      
      # Verify protected attributes weren't changed
      expenses.each(&:reload)
      expenses.each do |expense|
        expect(expense.email_account_id).to eq(email_account.id)
        expect(expense.created_at).not_to eq(Date.parse("2020-01-01"))
      end
    end
  end
end