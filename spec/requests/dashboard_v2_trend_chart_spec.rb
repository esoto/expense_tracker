# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard V2 Trend Chart", type: :request, unit: true do
  let(:admin_user) { create(:user, :admin) }

  before do
    sign_in_admin(admin_user)

    # Mock SolidQueue::Job used by DashboardService#sync_info
    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "GET /dashboard trend chart section" do
    context "with trend data and budget" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Alimentación") }

      let!(:expenses) do
        6.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            amount: 100_000 + (i * 10_000),
            transaction_date: i.months.ago.to_date,
            merchant_name: "Trend Merchant #{i} #{SecureRandom.hex(4)}")
        end
      end

      let!(:budget) do
        create(:budget,
          email_account: email_account,
          amount: 500_000,
          period: :monthly,
          category: nil)
      end

      it "renders the line chart with spending data" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Chartkick["LineChart"]')
      end

      it "renders the Monthly Trend heading" do
        get "/dashboard"

        expect(response.body).to include("Monthly Trend")
      end

      it "includes teal color for spending line" do
        get "/dashboard"

        expect(response.body).to include("#0F766E")
      end

      it "includes amber color for budget line" do
        get "/dashboard"

        expect(response.body).to include("#D97706")
      end

      it "shows the budget line label" do
        get "/dashboard"

        expect(response.body).to include("Budget")
      end

      it "shows the spending line label" do
        get "/dashboard"

        expect(response.body).to include("Spending")
      end

      it "includes the chart-skeleton controller wrapper" do
        get "/dashboard"

        expect(response.body).to include('data-controller="chart-skeleton"')
      end

      it "does not render the placeholder text" do
        get "/dashboard"

        expect(response.body).not_to include("Trend chart coming soon")
      end
    end

    context "with trend data but no budget" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Transporte") }

      let!(:expenses) do
        3.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            amount: 50_000,
            transaction_date: i.months.ago.to_date,
            merchant_name: "NoBudget Merchant #{i} #{SecureRandom.hex(4)}")
        end
      end

      it "renders the line chart with only spending data" do
        get "/dashboard"

        body = response.body
        expect(body).to include('Chartkick["LineChart"]')
        expect(body).to include("Spending")
      end

      it "renders only one data series without a budget line" do
        get "/dashboard"

        body = response.body
        # Chartkick renders series data as JSON with "name" keys
        # Only "Spending" series should be present, not "Budget"
        expect(body).to include('"name":"Spending"')
        expect(body).not_to include('"name":"Budget"')
      end
    end

    context "without trend data" do
      it "renders the empty state message" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("No hay datos de tendencia")
      end

      it "does not render a line chart" do
        get "/dashboard"

        expect(response.body).not_to include('Chartkick["LineChart"]')
      end

      it "renders the line chart icon in empty state" do
        get "/dashboard"

        # SVG path element for line chart icon
        expect(response.body).to include("M3 17l6-6 4 4 8-8")
      end
    end
  end
end
