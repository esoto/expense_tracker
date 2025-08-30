require "rails_helper"

RSpec.describe BudgetsController, type: :controller, unit: true do
  let(:email_account) { build_stubbed(:email_account) }
  let(:budget) { build_stubbed(:budget, email_account: email_account) }
  let(:category) { build_stubbed(:category) }

  before do
    allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
  end

  describe "before_actions", unit: true do
    it "sets email account for all actions" do
      expect(controller).to receive(:set_email_account).and_call_original
      get :index
    end

    it "sets budget for specific actions" do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(budget)
      allow(budget).to receive(:current_spend_amount).and_return(0)
      allow(budget).to receive(:usage_percentage).and_return(0)
      allow(budget).to receive(:remaining_amount).and_return(0)
      allow(budget).to receive(:historical_adherence).and_return([])
      allow(controller).to receive(:days_remaining_in_period).and_return(0)
      allow(controller).to receive(:calculate_daily_average_needed).and_return(0)
      
      expect(controller).to receive(:set_budget).and_call_original
      get :show, params: { id: budget.id }
    end
  end

  describe "GET #index", unit: true do
    let(:budgets_relation) { double("budgets_relation") }
    let(:budgets) { [budget] }

    before do
      allow(email_account).to receive(:budgets).and_return(budgets_relation)
      allow(budgets_relation).to receive_message_chain(:includes, :order).and_return(budgets)
      allow(budgets).to receive(:group_by).and_return({ monthly: [budget] })
      allow(controller).to receive(:calculate_overall_budget_health).and_return({ status: :good })
    end

    it "loads budgets for the email account" do
      expect(email_account).to receive(:budgets).and_return(budgets_relation)
      expect(budgets_relation).to receive(:includes).with(:category).and_return(budgets_relation)
      expect(budgets_relation).to receive(:order).with(active: :desc, period: :asc, created_at: :desc).and_return(budgets)
      
      get :index
    end

    it "groups budgets by period" do
      expect(budgets).to receive(:group_by)
      
      get :index
      expect(assigns(:budgets_by_period)).to eq({ monthly: [budget] })
    end

    it "calculates overall budget health" do
      expect(controller).to receive(:calculate_overall_budget_health)
      
      get :index
      expect(assigns(:overall_health)).to eq({ status: :good })
    end

    it "renders the index template" do
      get :index
      expect(response).to render_template(:index)
    end
  end

  describe "GET #show", unit: true do
    before do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(budget)
      allow(budget).to receive(:current_spend_amount).and_return(5000)
      allow(budget).to receive(:usage_percentage).and_return(50)
      allow(budget).to receive(:remaining_amount).and_return(5000)
      allow(budget).to receive(:historical_adherence).and_return([])
      allow(controller).to receive(:days_remaining_in_period).and_return(15)
      allow(controller).to receive(:calculate_daily_average_needed).and_return(333.33)
    end

    it "sets budget from params" do
      expect(email_account).to receive_message_chain(:budgets, :find).with(budget.id.to_s).and_return(budget)
      
      get :show, params: { id: budget.id }
      expect(assigns(:budget)).to eq(budget)
    end

    it "calculates budget statistics" do
      get :show, params: { id: budget.id }
      
      stats = assigns(:budget_stats)
      expect(stats).to include(
        current_spend: 5000,
        usage_percentage: 50,
        remaining: 5000,
        days_remaining: 15,
        daily_average_needed: 333.33,
        historical_data: []
      )
    end

    it "renders the show template" do
      get :show, params: { id: budget.id }
      expect(response).to render_template(:show)
    end
  end

  describe "GET #new", unit: true do
    let(:budgets_relation) { double("budgets_relation") }
    let(:new_budget) { build_stubbed(:budget) }
    let(:categories) { [category] }

    before do
      allow(email_account).to receive(:budgets).and_return(budgets_relation)
      allow(budgets_relation).to receive(:build).and_return(new_budget)
      allow(Category).to receive_message_chain(:all, :order).and_return(categories)
    end

    it "builds new budget with default values" do
      expect(budgets_relation).to receive(:build).with(
        start_date: Date.current,
        period: "monthly",
        currency: "CRC",
        warning_threshold: 70,
        critical_threshold: 90
      ).and_return(new_budget)
      
      get :new
      expect(assigns(:budget)).to eq(new_budget)
    end

    it "loads categories for select options" do
      expect(Category).to receive_message_chain(:all, :order).with(:name).and_return(categories)
      
      get :new
      expect(assigns(:categories)).to eq(categories)
    end

    it "renders the new template" do
      get :new
      expect(response).to render_template(:new)
    end
  end

  describe "GET #edit", unit: true do
    let(:categories) { [category] }

    before do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(budget)
      allow(Category).to receive_message_chain(:all, :order).and_return(categories)
    end

    it "sets budget from params" do
      expect(email_account).to receive_message_chain(:budgets, :find).with(budget.id.to_s)
      
      get :edit, params: { id: budget.id }
      expect(assigns(:budget)).to eq(budget)
    end

    it "loads categories for select options" do
      expect(Category).to receive_message_chain(:all, :order).with(:name)
      
      get :edit, params: { id: budget.id }
      expect(assigns(:categories)).to eq(categories)
    end

    it "renders the edit template" do
      get :edit, params: { id: budget.id }
      expect(response).to render_template(:edit)
    end
  end

  describe "POST #create", unit: true do
    let(:budgets_relation) { double("budgets_relation") }
    let(:new_budget) { build_stubbed(:budget) }
    let(:budget_params) { { name: "Test Budget", amount: 10000 } }

    before do
      allow(email_account).to receive(:budgets).and_return(budgets_relation)
      allow(budgets_relation).to receive(:build).and_return(new_budget)
    end

    context "with valid parameters" do
      before do
        allow(new_budget).to receive(:save).and_return(true)
        allow(new_budget).to receive(:calculate_current_spend!)
      end

      it "builds budget with permitted params" do
        expect(budgets_relation).to receive(:build)
        
        post :create, params: { budget: budget_params }
      end

      it "saves the budget" do
        expect(new_budget).to receive(:save).and_return(true)
        
        post :create, params: { budget: budget_params }
      end

      it "calculates initial spend" do
        expect(new_budget).to receive(:calculate_current_spend!)
        
        post :create, params: { budget: budget_params }
      end

      it "redirects to dashboard with success message" do
        post :create, params: { budget: budget_params }
        
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to eq("Presupuesto creado exitosamente.")
      end
    end

    context "with invalid parameters" do
      let(:categories) { [category] }

      before do
        allow(new_budget).to receive(:save).and_return(false)
        allow(Category).to receive_message_chain(:all, :order).and_return(categories)
      end

      it "does not save the budget" do
        expect(new_budget).to receive(:save).and_return(false)
        
        post :create, params: { budget: budget_params }
      end

      it "loads categories for form" do
        expect(Category).to receive_message_chain(:all, :order).with(:name)
        
        post :create, params: { budget: budget_params }
        expect(assigns(:categories)).to eq(categories)
      end

      it "renders new template with unprocessable content status" do
        post :create, params: { budget: budget_params }
        
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "PATCH #update", unit: true do
    let(:budget_params) { { name: "Updated Budget", amount: 15000 } }
    let(:categories) { [category] }

    before do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(budget)
    end

    context "with valid parameters" do
      before do
        allow(budget).to receive(:update).and_return(true)
        allow(budget).to receive(:calculate_current_spend!)
      end

      it "updates budget with permitted params" do
        expect(budget).to receive(:update)
        
        patch :update, params: { id: budget.id, budget: budget_params }
      end

      it "recalculates spend after update" do
        expect(budget).to receive(:calculate_current_spend!)
        
        patch :update, params: { id: budget.id, budget: budget_params }
      end

      it "redirects to dashboard with success message" do
        patch :update, params: { id: budget.id, budget: budget_params }
        
        expect(response).to redirect_to(dashboard_expenses_path)
        expect(flash[:notice]).to eq("Presupuesto actualizado exitosamente.")
      end
    end

    context "with invalid parameters" do
      before do
        allow(budget).to receive(:update).and_return(false)
        allow(Category).to receive_message_chain(:all, :order).and_return(categories)
      end

      it "does not update the budget" do
        expect(budget).to receive(:update).and_return(false)
        
        patch :update, params: { id: budget.id, budget: budget_params }
      end

      it "loads categories for form" do
        expect(Category).to receive_message_chain(:all, :order).with(:name)
        
        patch :update, params: { id: budget.id, budget: budget_params }
        expect(assigns(:categories)).to eq(categories)
      end

      it "renders edit template with unprocessable content status" do
        patch :update, params: { id: budget.id, budget: budget_params }
        
        expect(response).to render_template(:edit)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE #destroy", unit: true do
    before do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(budget)
      allow(budget).to receive(:destroy)
    end

    it "destroys the budget" do
      expect(budget).to receive(:destroy)
      
      delete :destroy, params: { id: budget.id }
    end

    it "redirects to budgets path with success message" do
      delete :destroy, params: { id: budget.id }
      
      expect(response).to redirect_to(budgets_path)
      expect(flash[:notice]).to eq("Presupuesto eliminado exitosamente.")
    end
  end

  describe "POST #duplicate", unit: true do
    let(:original_budget) { build_stubbed(:budget) }
    let(:duplicated_budget) { build_stubbed(:budget, id: 999) }

    before do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(original_budget)
    end

    context "when duplication succeeds" do
      before do
        allow(original_budget).to receive(:duplicate_for_next_period).and_return(duplicated_budget)
        allow(duplicated_budget).to receive(:persisted?).and_return(true)
      end

      it "duplicates the budget for next period" do
        expect(original_budget).to receive(:duplicate_for_next_period)
        
        post :duplicate, params: { id: original_budget.id }
      end

      it "redirects to edit new budget with success message" do
        post :duplicate, params: { id: original_budget.id }
        
        expect(response).to redirect_to(edit_budget_path(duplicated_budget))
        expect(flash[:notice]).to eq("Presupuesto duplicado exitosamente. Puedes ajustar los valores según necesites.")
      end
    end

    context "when duplication fails" do
      before do
        allow(original_budget).to receive(:duplicate_for_next_period).and_return(duplicated_budget)
        allow(duplicated_budget).to receive(:persisted?).and_return(false)
      end

      it "redirects to budgets path with error message" do
        post :duplicate, params: { id: original_budget.id }
        
        expect(response).to redirect_to(budgets_path)
        expect(flash[:alert]).to eq("No se pudo duplicar el presupuesto.")
      end
    end
  end

  describe "POST #deactivate", unit: true do
    let(:budget_to_deactivate) { build_stubbed(:budget) }

    before do
      allow(email_account).to receive_message_chain(:budgets, :find).and_return(budget_to_deactivate)
      allow(budget_to_deactivate).to receive(:deactivate!)
    end

    it "deactivates the budget" do
      expect(budget_to_deactivate).to receive(:deactivate!)
      
      post :deactivate, params: { id: budget_to_deactivate.id }
    end

    it "redirects to budgets path with success message" do
      post :deactivate, params: { id: budget_to_deactivate.id }
      
      expect(response).to redirect_to(budgets_path)
      expect(flash[:notice]).to eq("Presupuesto desactivado exitosamente.")
    end
  end

  describe "GET #quick_set", unit: true do
    let(:budgets_relation) { double("budgets_relation") }
    let(:new_budget) { build_stubbed(:budget) }

    before do
      allow(email_account).to receive(:budgets).and_return(budgets_relation)
      allow(budgets_relation).to receive(:build).and_return(new_budget)
      allow(controller).to receive(:calculate_suggested_budget_amount).and_return(50000)
      allow(I18n).to receive(:t).and_return("mensual")
    end

    it "sets default period" do
      get :quick_set
      expect(assigns(:period)).to eq("monthly")
    end

    it "uses provided period parameter" do
      get :quick_set, params: { period: "weekly" }
      expect(assigns(:period)).to eq("weekly")
    end

    it "calculates suggested budget amount" do
      expect(controller).to receive(:calculate_suggested_budget_amount).with("weekly")
      
      get :quick_set, params: { period: "weekly" }
      expect(assigns(:suggested_amount)).to eq(50000)
    end

    it "builds new budget with suggested values" do
      expect(budgets_relation).to receive(:build).with(hash_including(
        period: "monthly",
        amount: 50000,
        currency: "CRC",
        start_date: Date.current,
        warning_threshold: 70,
        critical_threshold: 90
      ))
      
      get :quick_set
    end

    context "with HTML format" do
      it "responds successfully" do
        get :quick_set
        expect(response).to have_http_status(:success)
      end
    end

    context "with Turbo Stream format" do
      it "responds to turbo_stream format" do
        get :quick_set, format: :turbo_stream
        expect(response.content_type).to include("turbo-stream")
      end
    end
  end

  describe "private methods", unit: true do
    describe "budget_params", unit: true do
      let(:params_hash) do
        {
          budget: {
            name: "Test Budget",
            amount: 10000,
            period: "monthly",
            unauthorized_param: "should_not_be_permitted"
          }
        }
      end

      before do
        controller.params = ActionController::Parameters.new(params_hash)
      end

      it "permits only allowed parameters" do
        permitted_params = controller.send(:budget_params)
        
        expect(permitted_params).to include("name", "amount", "period")
        expect(permitted_params).not_to include("unauthorized_param")
      end
    end
  end

  describe "error handling", unit: true do
    context "when email account is not found" do
      before do
        allow(EmailAccount).to receive_message_chain(:active, :first).and_return(nil)
      end

      it "redirects to root path" do
        get :index
        expect(response).to redirect_to(root_path)
      end
    end

    context "when budget is not found" do
      before do
        allow(email_account).to receive_message_chain(:budgets, :find).and_raise(ActiveRecord::RecordNotFound)
      end

      it "raises RecordNotFound error" do
        expect {
          get :show, params: { id: 999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "authorization", unit: true do
    it "scopes all budgets to email account" do
      allow(email_account).to receive_message_chain(:budgets, :includes, :order).and_return([])
      allow(controller).to receive(:calculate_overall_budget_health).and_return({})
      
      get :index
      expect(email_account).to have_received(:budgets)
    end
  end
end