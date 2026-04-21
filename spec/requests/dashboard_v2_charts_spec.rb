# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard V2 Charts", type: :request, unit: true do
  let(:admin_user) { create(:user, :admin) }

  before do
    sign_in_admin(admin_user)

    # Mock SolidQueue::Job used by DashboardService#sync_info
    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "GET /dashboard charts section" do
    context "with category data" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:food_category) { create(:category, name: "Alimentación") }
      let!(:transport_category) { create(:category, name: "Transporte") }

      let!(:food_expenses) do
        3.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: food_category,
            transaction_date: Date.current,
            merchant_name: "Food Merchant #{i} #{SecureRandom.hex(4)}")
        end
      end

      let!(:transport_expenses) do
        2.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: transport_category,
            transaction_date: Date.current,
            merchant_name: "Transport Merchant #{i} #{SecureRandom.hex(4)}")
        end
      end

      it "renders the charts row partial" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Category Breakdown")
      end

      it "renders the category horizontal bar chart" do
        get "/dashboard"

        body = response.body
        # Chartkick bar_chart renders a script instantiating BarChart
        expect(body).to include('Chartkick["BarChart"]')
      end

      it "renders the monthly trend placeholder" do
        get "/dashboard"

        body = response.body
        expect(body).to include("Monthly Trend")
      end

      it "includes the chart-skeleton controller wrapper" do
        get "/dashboard"

        expect(response.body).to include('data-controller="chart-skeleton"')
      end

      it "uses teal color for chart" do
        get "/dashboard"

        expect(response.body).to include("#0F766E")
      end
    end

    context "without category data" do
      it "renders the empty state message" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No hay datos de categorías")
      end

      it "does not render a bar chart when no data exists" do
        get "/dashboard"

        expect(response.body).not_to include('Chartkick["BarChart"]')
      end
    end
  end
end
