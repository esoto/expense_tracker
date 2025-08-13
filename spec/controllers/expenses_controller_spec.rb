require 'rails_helper'

RSpec.describe ExpensesController, type: :controller do
  let(:email_account) { create(:email_account) }
  let(:category) { create(:category, name: "Food", color: "#10B981") }

  describe "GET #index" do
    before do
      # Create expenses for different periods
      @today_expense = create(:expense,
        email_account: email_account,
        category: category,
        transaction_date: Date.current,
        amount: 1000,
        merchant_name: "Today Shop"
      )

      @week_expense = create(:expense,
        email_account: email_account,
        category: category,
        transaction_date: Date.current - 1.day,
        amount: 2000,
        merchant_name: "Week Shop"
      )

      @month_expense = create(:expense,
        email_account: email_account,
        category: category,
        transaction_date: Date.current.beginning_of_month + 5.days,
        amount: 3000,
        merchant_name: "Month Shop"
      )

      @last_month_expense = create(:expense,
        email_account: email_account,
        category: category,
        transaction_date: Date.current.last_month,
        amount: 4000,
        merchant_name: "Last Month Shop"
      )

      @year_expense = create(:expense,
        email_account: email_account,
        category: category,
        transaction_date: Date.current.beginning_of_year,
        amount: 5000,
        merchant_name: "Year Shop"
      )
    end

    context "without filters" do
      it "returns all expenses" do
        get :index
        expect(assigns(:expenses).count).to eq(5)
        expect(response).to have_http_status(:success)
      end

      it "calculates summary statistics correctly" do
        get :index
        expect(assigns(:total_amount)).to eq(15000)
        expect(assigns(:expense_count)).to eq(5)
      end
    end

    context "with period filter from dashboard" do
      it "filters expenses for today" do
        get :index, params: { period: "day", filter_type: "dashboard_metric" }

        expect(assigns(:expenses).count).to eq(1)
        expect(assigns(:expenses).first).to eq(@today_expense)
        expect(assigns(:from_dashboard)).to be true
        expect(assigns(:active_period)).to eq("day")
      end

      it "filters expenses for current week" do
        get :index, params: { period: "week", filter_type: "dashboard_metric" }

        expenses = assigns(:expenses)
        expect(expenses).to include(@today_expense)
        expect(expenses).to include(@week_expense)
        expect(expenses).not_to include(@last_month_expense)
        expect(assigns(:active_period)).to eq("week")
      end

      it "filters expenses for current month" do
        get :index, params: { period: "month", filter_type: "dashboard_metric" }

        expenses = assigns(:expenses)
        expect(expenses).to include(@today_expense)
        expect(expenses).to include(@week_expense)
        expect(expenses).to include(@month_expense)
        expect(expenses).not_to include(@last_month_expense)
        expect(assigns(:active_period)).to eq("month")
      end

      it "filters expenses for current year" do
        get :index, params: { period: "year", filter_type: "dashboard_metric" }

        expenses = assigns(:expenses)
        # Should include all expenses from the current year
        expect(expenses).to include(@today_expense)
        expect(expenses).to include(@week_expense)
        expect(expenses).to include(@month_expense)
        expect(expenses).to include(@year_expense)
        # Last month expense is still in current year unless we're in January
        if Date.current.month > 1
          expect(expenses).to include(@last_month_expense)
        end
        expect(assigns(:active_period)).to eq("year")
      end
    end

    context "with explicit date range from dashboard" do
      it "filters expenses within date range" do
        date_from = Date.current.beginning_of_month
        date_to = Date.current.end_of_month

        get :index, params: {
          date_from: date_from.to_s,
          date_to: date_to.to_s,
          filter_type: "dashboard_metric"
        }

        expenses = assigns(:expenses)
        expect(expenses).to include(@today_expense)
        expect(expenses).to include(@month_expense)
        expect(expenses).not_to include(@last_month_expense)
        expect(assigns(:date_from)).to eq(date_from)
        expect(assigns(:date_to)).to eq(date_to)
      end
    end

    context "with traditional filters" do
      it "filters by category" do
        other_category = create(:category, name: "Transport")
        other_expense = create(:expense, category: other_category, email_account: email_account)

        get :index, params: { category: "Food" }

        expenses = assigns(:expenses)
        expect(expenses.count).to eq(5)
        expect(expenses).not_to include(other_expense)
      end

      it "filters by bank" do
        bac_expense = create(:expense, bank_name: "BAC", email_account: email_account)

        get :index, params: { bank: "BAC" }

        expenses = assigns(:expenses)
        expect(expenses.count).to eq(1)
        expect(expenses.first).to eq(bac_expense)
      end

      it "filters by date range" do
        start_date = Date.current.beginning_of_month
        end_date = Date.current.end_of_month

        get :index, params: { start_date: start_date.to_s, end_date: end_date.to_s }

        expenses = assigns(:expenses)
        expect(expenses).to include(@today_expense)
        expect(expenses).to include(@month_expense)
        expect(expenses).not_to include(@last_month_expense)
      end
    end

    context "filter description" do
      it "builds correct description for period filter" do
        get :index, params: { period: "month", filter_type: "dashboard_metric" }

        expect(assigns(:filter_description)).to eq("Gastos de este mes")
      end

      it "builds correct description for date range" do
        date_from = Date.new(2024, 1, 1)
        date_to = Date.new(2024, 1, 31)

        get :index, params: { date_from: date_from.to_s, date_to: date_to.to_s }

        expect(assigns(:filter_description)).to include("01/01/2024")
        expect(assigns(:filter_description)).to include("31/01/2024")
      end

      it "combines multiple filters in description" do
        get :index, params: {
          period: "month",
          category: "Food",
          bank: "BAC",
          filter_type: "dashboard_metric"
        }

        description = assigns(:filter_description)
        expect(description).to include("Gastos de este mes")
        expect(description).to include("Categoría: Food")
        expect(description).to include("Banco: BAC")
      end
    end

    context "navigation context" do
      it "sets scroll target when requested" do
        get :index, params: { scroll_to: "expense_list" }

        expect(assigns(:scroll_to)).to eq("expense_list")
      end

      it "identifies dashboard navigation" do
        get :index, params: { filter_type: "dashboard_metric" }

        expect(assigns(:from_dashboard)).to be true
      end

      it "does not set dashboard flag for regular navigation" do
        get :index

        expect(assigns(:from_dashboard)).to be false
      end
    end
  end

  describe "GET #dashboard" do
    it "returns success status" do
      get :dashboard
      expect(response).to have_http_status(:success)
    end

    it "loads metrics for all periods" do
      create(:expense, email_account: email_account, amount: 1000)

      get :dashboard

      expect(assigns(:total_metrics)).to be_present
      expect(assigns(:month_metrics)).to be_present
      expect(assigns(:week_metrics)).to be_present
      expect(assigns(:day_metrics)).to be_present
    end
  end
end
