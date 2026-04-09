require "rails_helper"

RSpec.describe "PER-422: Route swap — new dashboard is root", type: :request, unit: true do
  let(:admin_user) { create(:admin_user) }

  before do
    sign_in_admin(admin_user)

    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "root path" do
    it "serves the new dashboard at /" do
      get "/"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("dashboard")
    end

    it "renders DashboardController#show" do
      get "/"
      expect(assigns(:monthly_metrics)).to be_present
    end
  end

  describe "dashboard path" do
    it "still works as an alias" do
      get "/dashboard"
      expect(response).to have_http_status(:success)
    end
  end

  describe "old dashboard" do
    let!(:email_account) { create(:email_account, active: true) }

    it "is accessible at /old-dashboard" do
      get "/old-dashboard"
      expect(response).to have_http_status(:success)
    end

    it "is still accessible at /expenses/dashboard" do
      get dashboard_expenses_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "navigation links" do
    it "dashboard nav link points to new dashboard" do
      get "/"
      expect(response.body).to include("dashboard")
    end
  end
end
