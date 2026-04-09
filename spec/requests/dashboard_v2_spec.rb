require "rails_helper"

RSpec.describe "Dashboard", type: :request, unit: true do
  let(:admin_user) { create(:admin_user) }

  before do
    sign_in_admin(admin_user)

    # Mock SolidQueue::Job used by DashboardService#sync_info
    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "GET /dashboard" do
    context "when unauthenticated" do
      before { reset! }

      it "redirects to login" do
        get "/dashboard"
        expect(response).to redirect_to(admin_login_path)
      end
    end

    context "with data" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Food") }
      let!(:expenses) do
        10.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            transaction_date: Date.current,
            merchant_name: "Merchant #{i}"
          )
        end
      end

      it "renders successfully" do
        get "/dashboard"
        expect(response).to have_http_status(:success)
      end

      it "includes monthly metrics" do
        get "/dashboard"
        expect(response.body).to include("Month Total")
        expect(response.body).to include("Budget Remaining")
        expect(response.body).to include("Daily Average")
        expect(response.body).to include("Uncategorized")
      end

      it "limits recent expenses to 8" do
        get "/dashboard"
        expect(assigns(:recent_expenses).size).to eq(8)
      end

      it "provides category breakdown limited to 10" do
        get "/dashboard"
        expect(assigns(:category_breakdown)).to be_an(Array)
        expect(assigns(:category_breakdown).size).to be <= 10
      end

      it "provides monthly trend data limited to 6 months" do
        get "/dashboard"
        expect(assigns(:monthly_trend)).to be_a(Hash)
        expect(assigns(:monthly_trend).size).to be <= 6
      end

      it "provides sync status" do
        get "/dashboard"
        expect(assigns(:sync_status)).to include(:last_sync, :active)
      end

      it "provides daily average" do
        get "/dashboard"
        expect(assigns(:daily_average)).to be_a(Float)
        expect(assigns(:daily_average)).to be > 0
      end

      it "provides uncategorized count" do
        get "/dashboard"
        expect(assigns(:uncategorized_count)).to be_an(Integer)
      end

      it "provides budget data" do
        get "/dashboard"
        expect(assigns(:budgets)).to be_present
      end
    end

    context "without email account" do
      it "renders successfully with empty defaults" do
        get "/dashboard"
        expect(response).to have_http_status(:success)
        expect(assigns(:monthly_metrics)[:total_amount]).to eq(0.0)
        expect(assigns(:daily_average)).to eq(0.0)
        expect(assigns(:uncategorized_count)).to eq(0)
      end
    end

    context "does not include expense management data" do
      let!(:email_account) { create(:email_account, active: true) }

      it "has no filters, batch selection, or pagination" do
        get "/dashboard"
        body = response.body

        # No expense management controls
        expect(body).not_to include("bulk_update_status")
        expect(body).not_to include("bulk_destroy")
        expect(body).not_to include("pagination")
      end
    end
  end
end
