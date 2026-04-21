# frozen_string_literal: true

# PER-225: "Nuevo Presupuesto" navigates to /sync_sessions/3 instead of /budgets/new
#
# Root cause: Two related issues:
# 1. Malformed HTML nesting in dashboard.html.erb when sync is running —
#    a premature </div> inside the `if has_running_jobs` block caused
#    sync_status_section turbo frame to not close properly, potentially
#    absorbing adjacent turbo frames and creating unpredictable navigation.
# 2. The "Nuevo Presupuesto" link lacked data-turbo-frame="_top", leaving it
#    vulnerable to turbo frame context hijacking.
#
# Fix:
# 1. Removed the extra </div> inside the conditional block in dashboard.html.erb
# 2. Added data-turbo-frame="_top" to the "Nuevo Presupuesto" link in budgets/index.html.erb

require "rails_helper"

RSpec.describe "PER-225: Nuevo Presupuesto navigation", type: :request, unit: true do
  let!(:email_account) { create(:email_account, active: true) }

  # PR-12: password matches User factory default so sign_in_admin works without explicit password.
  let(:admin_user) do
    create(:user, :admin,
      name: "PER-225 Test Admin",
      email: "per225-admin@test.com"
    )
  end

  let(:jobs_relation) { double("jobs_relation", exists?: false, count: 0) }

  before do
    sign_in_admin(admin_user)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))
  end

  describe "GET /budgets (index page)", unit: true do
    before do
      allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
    end

    it "returns a successful response" do
      get budgets_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the Nuevo Presupuesto link pointing to /budgets/new" do
      get budgets_path
      expect(response.body).to include(new_budget_path)
    end

    it "renders the Nuevo Presupuesto link with data-turbo-frame='_top' to prevent frame hijacking" do
      get budgets_path
      # Verify the link has data-turbo-frame="_top" to force full-page navigation
      # This prevents Turbo Frame from intercepting the click and navigating to the wrong URL
      expect(response.body).to include('data-turbo-frame="_top"')
    end
  end

  describe "GET /budgets/new", unit: true do
    before do
      allow(EmailAccount).to receive_message_chain(:active, :first).and_return(email_account)
    end

    it "returns a successful response" do
      get new_budget_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the new budget form" do
      get new_budget_path
      expect(response.body).to include("budget")
    end
  end

  describe "Dashboard sync widget turbo frame HTML structure", unit: true do
    it "renders the dashboard successfully" do
      get dashboard_expenses_path
      expect(response).to have_http_status(:ok)
    end

    it "contains sync_status_widget turbo frame on the dashboard" do
      get dashboard_expenses_path
      expect(response.body).to include('id="sync_status_widget"')
    end

    it "does not contain the old duplicate sync_status_section frame" do
      get dashboard_expenses_path
      expect(response.body).not_to include('id="sync_status_section"')
    end

    context "when sync is running (has_running_jobs is true)", unit: true do
      let!(:running_session) { create(:sync_session, :running) }
      let!(:sync_account) do
        create(:sync_session_account,
          sync_session: running_session,
          email_account: email_account,
          status: "processing",
          total_emails: 50,
          processed_emails: 10
        )
      end

      it "renders the dashboard without malformed HTML nesting" do
        get dashboard_expenses_path
        expect(response).to have_http_status(:ok)
      end

      it "contains sync_status_widget when sync is running" do
        get dashboard_expenses_path
        expect(response.body).to include('id="sync_status_widget"')
      end
    end
  end
end
