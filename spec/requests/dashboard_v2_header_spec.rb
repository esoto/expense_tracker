require "rails_helper"

RSpec.describe "Dashboard V2 Header", type: :request, unit: true do
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
    let!(:email_account) { create(:email_account, active: true) }

    context "header partial rendering" do
      it "renders the header with the dashboard title" do
        get "/dashboard"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("Dashboard")
      end

      it "renders a subtitle with the current month and year" do
        get "/dashboard"

        # The subtitle uses I18n.l with :long format — just check for the year
        expect(response.body).to include(Date.current.year.to_s)
      end
    end

    context "sync status indicator — idle state" do
      let!(:sync_session) do
        create(:sync_session, :completed, completed_at: 2.hours.ago)
      end

      it "displays time-ago text for last sync" do
        get "/dashboard"

        # Uses i18n key with default "Last synced %{time} ago"
        expect(response.body).to match(/synced.*ago|sincronizado/i)
      end

      it "uses slate-500 styling for idle state" do
        get "/dashboard"

        expect(response.body).to include("text-slate-500")
      end
    end

    context "sync status indicator — active state" do
      let!(:sync_session) do
        create(:sync_session, :running)
      end

      it "displays syncing text" do
        get "/dashboard"

        expect(response.body).to match(/Syncing|Sincronizando/i)
      end

      it "includes a spinner with animate-spin" do
        get "/dashboard"

        expect(response.body).to include("animate-spin")
      end

      it "uses teal-600 styling for active state" do
        get "/dashboard"

        expect(response.body).to include("text-teal-600")
      end
    end

    context "sync status indicator — never synced state" do
      it "displays not synced yet text when no sync has occurred" do
        get "/dashboard"

        expect(response.body).to match(/Not synced yet|No sincronizado/i)
      end

      it "uses slate-400 styling for never-synced state" do
        get "/dashboard"

        expect(response.body).to include("text-slate-400")
      end
    end

    context "accessibility" do
      it "includes aria-live polite on the sync status region" do
        get "/dashboard"

        expect(response.body).to include('aria-live="polite"')
      end
    end

    context "sync status section removed" do
      it "does not render the standalone sync status card with h2 heading" do
        get "/dashboard"

        # The old standalone sync status section had an h2 with "Sync Status".
        # The header indicator replaces it — no h2 should remain.
        expect(response.body).not_to include("Sync Status</h2>")
      end
    end
  end
end
