# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Budgets", type: :request, integration: true do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category) }
  let(:valid_attributes) do
    {
      budget: {
        name: 'Monthly Budget',
        amount: 100000,
        period: 'monthly',
        currency: 'CRC',
        start_date: Date.current,
        warning_threshold: 70,
        critical_threshold: 90
      }
    }
  end
  let(:invalid_attributes) do
    {
      budget: {
        name: '',
        amount: 0,
        period: ''
      }
    }
  end

  before do
    # Ensure we have an active email account
    allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
  end

  describe "POST /budgets", integration: true do
    context "with valid parameters" do
      it "creates a new Budget" do
        expect {
          post budgets_path, params: valid_attributes
        }.to change(Budget, :count).by(1)
      end

      it "redirects to the dashboard" do
        post budgets_path, params: valid_attributes
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to eq('Presupuesto creado exitosamente.')
      end

      it "calculates initial spend" do
        post budgets_path, params: valid_attributes
        budget = Budget.last
        expect(budget.current_spend_updated_at).not_to be_nil
      end
    end

    context "with invalid parameters" do
      it "does not create a new Budget" do
        expect {
          post budgets_path, params: invalid_attributes
        }.not_to change(Budget, :count)
      end

      it "returns unprocessable entity status" do
        post budgets_path, params: invalid_attributes
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH /budgets/:id", integration: true do
    let(:budget) { create(:budget, email_account: email_account) }
    let(:new_attributes) do
      {
        budget: {
          name: 'Updated Budget',
          amount: 150000
        }
      }
    end

    context "with valid parameters" do
      it "updates the requested budget" do
        patch budget_path(budget), params: new_attributes
        budget.reload
        expect(budget.name).to eq('Updated Budget')
        expect(budget.amount).to eq(150000)
      end

      it "recalculates spend after update" do
        original_updated_at = budget.current_spend_updated_at
        patch budget_path(budget), params: new_attributes
        budget.reload
        expect(budget.current_spend_updated_at).not_to eq(original_updated_at)
      end

      it "redirects to the dashboard" do
        patch budget_path(budget), params: new_attributes
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to eq('Presupuesto actualizado exitosamente.')
      end
    end

    context "with invalid parameters" do
      it "returns unprocessable entity status" do
        patch budget_path(budget), params: { budget: { name: '' } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /budgets/:id", integration: true do
    let!(:budget) { create(:budget, email_account: email_account) }

    it "destroys the requested budget" do
      expect {
        delete budget_path(budget)
      }.to change(Budget, :count).by(-1)
    end

    it "redirects to the budgets list" do
      delete budget_path(budget)
      expect(response).to redirect_to(budgets_path)
      expect(flash[:notice]).to eq('Presupuesto eliminado exitosamente.')
    end
  end

  describe "POST /budgets/:id/duplicate", integration: true do
    let(:original_budget) { create(:budget, email_account: email_account, period: 'monthly', active: false) }

    it "creates a duplicate budget for the next period" do
      original_budget # Force creation of the original budget
      expect {
        post duplicate_budget_path(original_budget)
      }.to change(Budget, :count).by(1)
    end

    it "redirects to edit the new budget" do
      post duplicate_budget_path(original_budget)
      new_budget = Budget.last
      expect(response).to redirect_to(edit_budget_path(new_budget))
      expect(flash[:notice]).to include('Presupuesto duplicado exitosamente')
    end
  end

  describe "POST /budgets/:id/deactivate", integration: true do
    let(:budget) { create(:budget, email_account: email_account, active: true) }

    it "deactivates the budget" do
      post deactivate_budget_path(budget)
      budget.reload
      expect(budget.active).to be false
    end

    it "redirects to budgets list with notice" do
      post deactivate_budget_path(budget)
      expect(response).to redirect_to(budgets_path)
      expect(flash[:notice]).to eq('Presupuesto desactivado exitosamente.')
    end
  end

  describe "GET /budgets/quick_set", integration: true do
    it "returns success for HTML format" do
      get quick_set_budgets_path, params: { period: 'monthly' }
      expect(response).to be_successful
    end

    it "returns turbo stream for turbo_stream format" do
      get quick_set_budgets_path(format: :turbo_stream), params: { period: 'monthly' }
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    end

    it "calculates suggested budget amount" do
      create(:expense, email_account: email_account, amount: 50000, transaction_date: 1.day.ago)
      get quick_set_budgets_path, params: { period: 'monthly' }
      expect(assigns(:suggested_amount)).to be > 0
    end
  end
end
