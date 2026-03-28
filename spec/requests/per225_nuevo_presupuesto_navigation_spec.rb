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

  let(:admin_user) do
    AdminUser.create!(
      name: "PER-225 Test Admin",
      email: "per225-admin@test.com",
      password: "AdminPassword123!",
      role: "admin"
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

  describe "Dashboard sync_status_section turbo frame HTML structure", unit: true do
    it "renders the dashboard successfully" do
      get dashboard_expenses_path
      expect(response).to have_http_status(:ok)
    end

    it "contains sync_status_section turbo frame on the dashboard" do
      get dashboard_expenses_path
      expect(response.body).to include('id="sync_status_section"')
    end

    it "contains sync_status_widget turbo frame on the dashboard" do
      get dashboard_expenses_path
      expect(response.body).to include('id="sync_status_widget"')
    end

    it "has sync_status_widget positioned after sync_status_section in the page" do
      get dashboard_expenses_path
      body = response.body

      # sync_status_widget (from unified_widget partial) must appear AFTER sync_status_section
      # This confirms the turbo frame boundaries are correct and the HTML nesting is valid.
      # Previously, a premature </div> inside the `if has_running_jobs` conditional block
      # caused sync_status_section to not close properly, extending its scope to incorrectly
      # absorb sync_status_widget and other subsequent content.
      sync_section_pos = body.index('id="sync_status_section"')
      sync_widget_pos = body.index('id="sync_status_widget"')

      expect(sync_section_pos).to be_present, "Expected sync_status_section turbo frame in dashboard"
      expect(sync_widget_pos).to be_present, "Expected sync_status_widget turbo frame in dashboard"
      expect(sync_widget_pos).to be > sync_section_pos,
        "sync_status_widget should appear after sync_status_section (not nested inside it)"
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

      it "still has sync_status_widget outside sync_status_section when sync is running" do
        get dashboard_expenses_path
        body = response.body

        sync_section_pos = body.index('id="sync_status_section"')
        sync_widget_pos = body.index('id="sync_status_widget"')

        expect(sync_section_pos).to be_present
        expect(sync_widget_pos).to be_present
        expect(sync_widget_pos).to be > sync_section_pos,
          "sync_status_widget should appear after sync_status_section even when sync is running"
      end
    end
  end
end
