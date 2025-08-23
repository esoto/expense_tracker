# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard Filter Chips AJAX", type: :request do
  let!(:email_account) { create(:email_account, active: true) }
  let!(:category1) { create(:category, name: "Food", color: "#10B981") }
  let!(:category2) { create(:category, name: "Transport", color: "#3B82F6") }

  let!(:food_expense) do
    create(:expense,
           email_account: email_account,
           category: category1,
           merchant_name: "Restaurant ABC",
           amount: 15000,
           status: "pending",
           transaction_date: Date.current,
           currency: "crc")
  end

  let!(:transport_expense) do
    create(:expense,
           email_account: email_account,
           category: category2,
           merchant_name: "Gas Station XYZ",
           amount: 30000,
           status: "processed",
           transaction_date: 1.day.ago,
           currency: "crc")
  end

  describe "GET /expenses/dashboard with filters" do
    context "with category filter" do
      it "returns filtered expenses via AJAX" do
        get dashboard_expenses_path,
            params: { category_ids: [ category1.id ], partial: "expenses_list" },
            headers: { "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Restaurant ABC")
        expect(response.body).not_to include("Gas Station XYZ")
      end
    end

    context "with status filter" do
      it "returns only pending expenses" do
        get dashboard_expenses_path,
            params: { status: "pending", partial: "expenses_list" },
            headers: { "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Restaurant ABC")
        expect(response.body).not_to include("Gas Station XYZ")
      end

      it "returns only processed expenses" do
        get dashboard_expenses_path,
            params: { status: "processed", partial: "expenses_list" },
            headers: { "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include("Restaurant ABC")
        expect(response.body).to include("Gas Station XYZ")
      end
    end

    context "with period filter" do
      it "returns expenses for today" do
        get dashboard_expenses_path,
            params: { period: "today", partial: "expenses_list" },
            headers: { "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Restaurant ABC")
        expect(response.body).not_to include("Gas Station XYZ")
      end

      it "returns expenses for this week" do
        get dashboard_expenses_path,
            params: { period: "week", partial: "expenses_list" },
            headers: { "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Restaurant ABC")
        expect(response.body).to include("Gas Station XYZ")
      end
    end

    context "with combined filters" do
      it "applies multiple filters correctly" do
        get dashboard_expenses_path,
            params: {
              category_ids: [ category1.id ],
              status: "pending",
              period: "today",
              partial: "expenses_list"
            },
            headers: { "X-Requested-With" => "XMLHttpRequest" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Restaurant ABC")
        expect(response.body).not_to include("Gas Station XYZ")
      end
    end

    context "without AJAX header" do
      it "returns full dashboard page" do
        get dashboard_expenses_path,
            params: { category_ids: [ category1.id ] }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Dashboard Financiero")
        expect(response.body).to include("Recent Expenses")
      end
    end
  end

  describe "performance" do
    before do
      # Create additional expenses for performance testing
      5.times do
        create(:expense,
               email_account: email_account,
               category: [ category1, category2 ].sample,
               amount: rand(10000..50000),
               status: [ "pending", "processed" ].sample,
               transaction_date: rand(0..30).days.ago,
               currency: "crc")
      end
    end

    it "responds within acceptable time" do
      start_time = Time.current

      get dashboard_expenses_path,
          params: { category_ids: [ category1.id ], partial: "expenses_list" },
          headers: { "X-Requested-With" => "XMLHttpRequest" }

      duration_ms = (Time.current - start_time) * 1000

      expect(response).to have_http_status(:success)
      expect(duration_ms).to be < 100 # Should respond within 100ms
    end
  end
end
