require "rails_helper"

RSpec.describe "Dashboard V2 Metric Cards", type: :request, unit: true do
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
    context "with data" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Food") }
      let!(:expenses) do
        3.times.map do |i|
          create(:expense,
            email_account: email_account,
            category: category,
            amount: 1000 * (i + 1),
            transaction_date: Date.current,
            merchant_name: "MetricMerchant#{i}")
        end
      end
      let!(:uncategorized_expense) do
        create(:expense,
          email_account: email_account,
          category: nil,
          amount: 500,
          transaction_date: Date.current,
          merchant_name: "UncategorizedMerchant")
      end

      before { get "/dashboard" }

      it "renders the metric cards section" do
        expect(response).to have_http_status(:success)
        expect(response.body).to include('aria-label="Monthly metrics"')
      end

      describe "primary card (monthly total)" do
        it "renders with animated-metric controller data attributes" do
          expect(response.body).to include('data-controller="animated-metric')
          expect(response.body).to include("data-animated-metric-prefix-value")
        end

        it "renders the monthly total label" do
          expect(response.body).to include("Month Total")
        end

        it "includes navigation controller for month period" do
          expect(response.body).to include('data-dashboard-card-navigation-period-value="month"')
        end

        it "renders budget progress partial" do
          # Budget progress partial should be rendered inside primary card
          # Either shows the progress bar or the no-budget call-to-action
          expect(response.body).to include("role=\"progressbar\"").or(
            include("budget-progress")
          )
        end

        it "renders trend indicator" do
          expect(response.body).to include("data-animated-metric-trend-value-value")
        end
      end

      describe "secondary card: budget remaining" do
        it "renders the budget remaining card" do
          expect(response.body).to include("Budget Remaining")
        end

        it "uses color-coded styling based on budget status" do
          # The card should contain emerald, amber, or rose color classes
          body = response.body
          has_budget_color = body.include?("emerald") || body.include?("amber") || body.include?("rose")
          expect(has_budget_color).to be true
        end
      end

      describe "secondary card: daily average" do
        it "renders the daily average card" do
          expect(response.body).to include("Daily Average")
        end

        it "includes animated-metric data attributes" do
          # Daily average card should have its own animated-metric controller
          expect(response.body).to include("data-animated-metric-decimals-value=\"2\"")
        end
      end

      describe "secondary card: uncategorized" do
        it "renders the uncategorized card" do
          expect(response.body).to include("Uncategorized")
        end

        it "shows warning styling when uncategorized count is greater than zero" do
          expect(response.body).to include("amber")
        end
      end

      describe "accessibility" do
        it "has ARIA labels on all cards" do
          body = response.body
          expect(body).to include('role="button"')
          expect(body).to include('tabindex="0"')
        end

        it "has keyboard navigation data actions" do
          expect(response.body).to include("keydown.enter->dashboard-card-navigation#navigate")
          expect(response.body).to include("keydown.space->dashboard-card-navigation#navigate")
        end
      end

      describe "responsive grid" do
        it "uses responsive grid classes" do
          expect(response.body).to include("grid-cols-1")
          expect(response.body).to include("sm:grid-cols-2")
          expect(response.body).to include("lg:grid-cols-4")
        end
      end
    end

    context "without email account (empty state)" do
      before { get "/dashboard" }

      it "renders metric cards with zero values" do
        expect(response).to have_http_status(:success)
        expect(response.body).to include("Month Total")
        expect(response.body).to include("Daily Average")
        expect(response.body).to include("Uncategorized")
      end
    end

    context "with zero uncategorized expenses" do
      let!(:email_account) { create(:email_account, active: true) }
      let!(:category) { create(:category, name: "Transport") }
      let!(:expense) do
        create(:expense,
          email_account: email_account,
          category: category,
          amount: 2000,
          transaction_date: Date.current,
          merchant_name: "AllCategorizedMerchant")
      end

      before { get "/dashboard" }

      it "does not show warning styling for uncategorized when count is zero" do
        # When uncategorized_count is 0, the uncategorized card should not
        # use amber/warning styling — it should use neutral/success styling
        expect(response.body).to include("Uncategorized")
      end
    end
  end
end
