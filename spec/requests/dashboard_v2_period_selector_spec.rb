require "rails_helper"

RSpec.describe "Dashboard Period Selector", type: :request, unit: true do
  let(:admin_user) { create(:user, :admin) }

  before do
    sign_in_admin(admin_user)

    # Mock SolidQueue::Job used by DashboardService#sync_info
    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "GET /dashboard" do
    let!(:email_account) { create(:email_account, active: true) }
    let!(:category) { create(:category, name: "Food") }
    let!(:expense) do
      create(:expense,
        email_account: email_account,
        category: category,
        transaction_date: Date.current,
        merchant_name: "Test Merchant")
    end

    context "period defaults" do
      it "defaults period to month when no param given" do
        get "/dashboard"
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("month")
      end
    end

    context "period selector rendering" do
      it "renders a period selector with 4 options" do
        get "/dashboard"
        body = response.body

        expect(body).to include("This Month")
        expect(body).to include("Last Month")
        expect(body).to include("This Quarter")
        expect(body).to include("This Year")
      end

      it "highlights the active period with teal styling" do
        get "/dashboard"
        # Default "month" should be active
        expect(response.body).to include("bg-teal-700")
      end

      it "renders inactive periods with slate styling" do
        get "/dashboard"
        expect(response.body).to include("bg-slate-100")
      end
    end

    context "Turbo Frame wrapper" do
      it "wraps dashboard body in a turbo frame" do
        get "/dashboard"
        expect(response.body).to include('id="dashboard-body"')
      end

      it "period selector links target the dashboard-body frame" do
        get "/dashboard"
        expect(response.body).to include('data-turbo-frame="dashboard-body"')
      end
    end

    context "period=month (default)" do
      it "uses current month reference date" do
        get "/dashboard", params: { period: "month" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("month")
      end
    end

    context "period=last_month" do
      it "uses previous month reference date" do
        get "/dashboard", params: { period: "last_month" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("last_month")
      end

      it "passes last month reference date to MetricsCalculator" do
        expected_date = 1.month.ago.to_date

        expect(Services::MetricsCalculator).to receive(:new).with(
          hash_including(reference_date: expected_date)
        ).and_call_original

        get "/dashboard", params: { period: "last_month" }
      end
    end

    context "period=quarter" do
      it "uses quarter period" do
        get "/dashboard", params: { period: "quarter" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("quarter")
      end
    end

    context "period=year" do
      it "uses yearly period for MetricsCalculator" do
        expect(Services::MetricsCalculator).to receive(:new).with(
          hash_including(period: :year)
        ).and_call_original

        get "/dashboard", params: { period: "year" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("year")
      end
    end

    context "invalid period" do
      it "normalizes unknown period values to month" do
        get "/dashboard", params: { period: "invalid" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("month")
      end
    end

    context "named route" do
      it "responds to dashboard_page_path helper" do
        expect(dashboard_page_path).to eq("/dashboard")
      end

      it "accepts period param in named route" do
        expect(dashboard_page_path(period: "year")).to eq("/dashboard?period=year")
      end
    end

    context "without email account" do
      before { EmailAccount.destroy_all }

      it "renders successfully with default period" do
        get "/dashboard", params: { period: "last_month" }
        expect(response).to have_http_status(:success)
        expect(assigns(:period)).to eq("last_month")
      end
    end
  end
end
