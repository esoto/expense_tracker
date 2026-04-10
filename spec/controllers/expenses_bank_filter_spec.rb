require "rails_helper"

RSpec.describe ExpensesController, type: :controller, unit: true do
  let(:bac_account) { create(:email_account, bank_name: "BAC", active: true) }
  let(:bcr_account) { create(:email_account, bank_name: "BCR", active: true) }
  let(:inactive_account) { create(:email_account, :inactive, bank_name: "Scotiabank") }

  let(:filter_service) { double("Services::ExpenseFilterService") }
  let(:service_result) do
    double("ServiceResult", {
      success?: true,
      expenses: [],
      total_count: 0,
      performance_metrics: { query_time: 10 },
      metadata: {
        filters_applied: {},
        page: 1,
        per_page: 25
      }
    })
  end

  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:authorize_expense!).and_return(true)
    allow(controller).to receive(:current_user_email_accounts).and_return(
      EmailAccount.where(id: [ bac_account.id, bcr_account.id, inactive_account.id ])
    )

    allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
    allow(filter_service).to receive(:call).and_return(service_result)
    allow(controller).to receive(:setup_navigation_context)
    allow(controller).to receive(:calculate_summary_statistics)
    allow(controller).to receive(:build_filter_description).and_return("")
  end

  describe "GET #index bank filter dropdown", unit: true do
    context "when active EmailAccount records exist with different bank names" do
      before do
        bac_account
        bcr_account
        inactive_account
      end

      it "assigns @bank_names from active EmailAccount records" do
        get :index

        expect(assigns(:bank_names)).to be_present
      end

      it "includes bank names from active accounts" do
        get :index

        expect(assigns(:bank_names)).to include("BAC")
        expect(assigns(:bank_names)).to include("BCR")
      end

      it "excludes bank names from inactive accounts" do
        get :index

        expect(assigns(:bank_names)).not_to include("Scotiabank")
      end

      it "does not include hardcoded bank names that are not in the database" do
        get :index

        # Ensure the dropdown is data-driven, not hardcoded
        # "Manual Entry" was hardcoded before but should only appear if in DB
        expect(assigns(:bank_names)).not_to include("Manual Entry")
      end

      it "returns an array without nil values" do
        get :index

        expect(assigns(:bank_names)).not_to include(nil)
      end

      it "returns unique bank names" do
        create(:email_account, bank_name: "BAC", active: true)

        get :index

        expect(assigns(:bank_names).count("BAC")).to eq(1)
      end
    end

    context "when no active EmailAccount records exist" do
      before do
        EmailAccount.update_all(active: false)
      end

      it "assigns an empty array for @bank_names" do
        get :index

        expect(assigns(:bank_names)).to eq([])
      end
    end
  end
end
