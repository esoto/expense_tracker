# frozen_string_literal: true

require "rails_helper"

# Covers the "needs attention" alert banner shared between the dashboard and
# the budgets index. Renders when the linked salary_calc external budget
# source is deactivated (rose, reconnect required) or its last scheduled
# sync failed while still active (amber, sync failed).
RSpec.describe "External source alert banner", type: :request, unit: true do
  let!(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user, active: true) }

  before do
    sign_in_admin(admin_user)

    # Mock SolidQueue::Job used by DashboardService#sync_info (dashboard#show only).
    jobs_relation = double("jobs_relation", exists?: false, count: 0)
    allow(SolidQueue::Job).to receive(:where)
      .with(class_name: "ProcessEmailsJob", finished_at: nil)
      .and_return(double("intermediate", where: jobs_relation))

    # BudgetsController scopes via scoping_user.email_accounts.first; the
    # dashboard scopes via EmailAccount.active.first — both resolve to the
    # same email_account here since admin_user has a single active account.
  end

  shared_examples "renders the external source alert banner" do |path_helper|
    context "when the source is deactivated" do
      let!(:source) do
        create(:external_budget_source, email_account: email_account, active: false, last_sync_status: "failed",
               last_sync_error: "token revoked")
      end

      it "renders the rose reconnect-required banner" do
        get send(path_helper)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('role="alert"')
        expect(response.body).to include(I18n.t("external_sources.alert.reconnect_required_title"))
        expect(response.body).to include(I18n.t("external_sources.alert.reconnect_required_body"))
        expect(response.body).to include("bg-rose-50")
        expect(response.body).not_to include(I18n.t("external_sources.alert.sync_failed_title"))
        expect(response.body).to match(%r{<a[^>]+href="#{Regexp.escape(external_source_path)}"[^>]*>#{Regexp.escape(I18n.t("external_sources.alert.cta"))}</a>})
      end
    end

    context "when the source is active but the last sync failed" do
      let!(:source) do
        create(:external_budget_source, email_account: email_account, active: true, last_sync_status: "failed",
               last_sync_error: "timeout")
      end

      it "renders the amber sync-failed banner" do
        get send(path_helper)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('role="alert"')
        expect(response.body).to include(I18n.t("external_sources.alert.sync_failed_title"))
        expect(response.body).to include(I18n.t("external_sources.alert.sync_failed_body"))
        expect(response.body).to include("bg-amber-50")
        expect(response.body).not_to include(I18n.t("external_sources.alert.reconnect_required_title"))
        expect(response.body).to match(%r{<a[^>]+href="#{Regexp.escape(external_source_path)}"[^>]*>#{Regexp.escape(I18n.t("external_sources.alert.cta"))}</a>})
      end
    end

    context "when the source is active and healthy" do
      let!(:source) do
        create(:external_budget_source, email_account: email_account, active: true, last_sync_status: "ok")
      end

      it "does not render the alert banner" do
        get send(path_helper)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(I18n.t("external_sources.alert.reconnect_required_title"))
        expect(response.body).not_to include(I18n.t("external_sources.alert.sync_failed_title"))
      end
    end

    context "when there is no external source" do
      it "does not render the alert banner" do
        get send(path_helper)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include(I18n.t("external_sources.alert.reconnect_required_title"))
        expect(response.body).not_to include(I18n.t("external_sources.alert.sync_failed_title"))
      end
    end
  end

  describe "GET /budgets" do
    include_examples "renders the external source alert banner", :budgets_path
  end

  describe "GET /dashboard" do
    include_examples "renders the external source alert banner", :dashboard_page_path
  end
end
