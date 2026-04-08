# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard V2 Recent Activity", type: :request, unit: true do
  let(:admin_user) { create(:admin_user) }

  before do
    sign_in_admin(admin_user)

    # Mock SolidQueue::Job used by DashboardService#sync_info
    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "GET /dashboard-v2" do
    context "recent activity section" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Alimentacion", color: "#4ECDC4") }

      let!(:expenses) do
        8.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            transaction_date: Date.current - i.days,
            merchant_name: "Merchant Activity #{i}",
            amount: 1000.0 + (i * 500)
          )
        end
      end

      it "renders the recent activity section" do
        get "/dashboard-v2"
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Recent Expenses")
      end

      it "shows merchant names" do
        get "/dashboard-v2"
        expenses.each do |expense|
          expect(response.body).to include(expense.merchant_name)
        end
      end

      it "shows formatted amounts with colon currency symbol" do
        get "/dashboard-v2"
        expect(response.body).to include("₡")
      end

      it "shows category badges" do
        get "/dashboard-v2"
        expect(response.body).to include("Alimentacion")
      end

      it "includes 'View all expenses' link" do
        get "/dashboard-v2"
        expect(response.body).to include("View all expenses")
        expect(response.body).to include(expenses_path)
      end

      it "displays a maximum of 8 expenses" do
        # Create 2 extra expenses beyond the 8 already created
        2.times do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            transaction_date: Date.current,
            merchant_name: "Extra Merchant #{i}"
          )
        end

        get "/dashboard-v2"
        expect(assigns(:recent_expenses).size).to eq(8)
      end
    end

    context "empty state" do
      let!(:email_account) { create(:email_account, active: true) }

      it "shows empty state message when there are no expenses" do
        get "/dashboard-v2"
        expect(response.body).to include("No hay gastos recientes")
      end
    end

    context "expense without category" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:uncategorized_expense) do
        create(:expense,
          email_account: email_account,
          category: nil,
          transaction_date: Date.current,
          merchant_name: "Uncategorized Merchant"
        )
      end

      it "shows 'Sin categoría' for expenses without a category" do
        get "/dashboard-v2"
        expect(response.body).to include("Sin categor")
      end
    end
  end
end
