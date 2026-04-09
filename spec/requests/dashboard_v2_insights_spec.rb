# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard V2 Insights", type: :request, unit: true do
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
    context "when insights exist" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Food") }
      let!(:uncategorized_expenses) do
        3.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: nil,
            amount: 500,
            transaction_date: Date.current,
            merchant_name: "UncatMerchant#{i}")
        end
      end

      it "renders the insights row section" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('aria-label="Actionable insights"')
      end

      it "displays uncategorized insight when uncategorized expenses exist" do
        get "/dashboard"

        expect(response.body).to include("expenses need categorization")
      end
    end

    context "when no insights trigger" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Food") }
      let!(:expense) do
        create(:expense,
          email_account: email_account,
          category: category,
          amount: 100,
          transaction_date: Date.current,
          merchant_name: "Merchant1")
      end

      it "does not render the insights row when no insights exist" do
        # No uncategorized expenses, and total_amount with no budget means no budget insights
        allow_any_instance_of(Services::DashboardInsightsService).to receive(:insights).and_return([])
        get "/dashboard"

        expect(response.body).not_to include('aria-label="Actionable insights"')
      end
    end

    context "with budget data showing spending projection" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Food") }
      let!(:budget) do
        create(:budget,
          email_account: email_account,
          category: nil,
          amount: 50_000.0,
          period: :monthly,
          start_date: Date.current.beginning_of_month)
      end
      let!(:expenses) do
        5.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            amount: 20_000,
            transaction_date: Date.current,
            merchant_name: "BudgetMerchant#{i}")
        end
      end

      it "renders spending projection insight" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        body = response.body
        expect(body).to include("Projected to exceed budget").or include("On track to stay within budget")
      end
    end
  end
end
