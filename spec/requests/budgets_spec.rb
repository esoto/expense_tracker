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
        critical_threshold: 90,
        email_account_id: email_account.id
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

  let(:user) { email_account.user }

  # PR-12: password matches User factory default so sign_in_admin works without explicit password.
  let(:admin_user) do
    create(:user, :admin,
      name: "Budget Test Admin",
      email: "budget-admin@test.com"
    )
  end

  before do
    sign_in_admin(admin_user)
    # Stub scoping_user to return the User who owns the email_account.
    allow_any_instance_of(BudgetsController).to receive(:scoping_user).and_return(user)
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

  describe "POST /budgets with multi-category + salary_bucket" do
    let(:food)  { create(:category, name: "Food Multi") }
    let(:trans) { create(:category, name: "Transport Multi") }

    let(:multi_attributes) do
      {
        budget: valid_attributes[:budget].merge(
          category_ids: [ food.id, trans.id ],
          salary_bucket: "fixed"
        )
      }
    end

    it "persists multiple claimed categories" do
      post budgets_path, params: multi_attributes
      expect(Budget.last.categories).to contain_exactly(food, trans)
    end

    it "persists the salary_bucket" do
      post budgets_path, params: multi_attributes
      expect(Budget.last.salary_bucket).to eq("fixed")
    end

    it "treats blank category_ids (hidden-input placeholder) as no selection" do
      attrs = multi_attributes.deep_dup
      attrs[:budget][:category_ids] = [ "" ]
      post budgets_path, params: attrs
      expect(Budget.last.categories).to be_empty
    end
  end
end
