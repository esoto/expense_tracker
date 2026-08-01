# frozen_string_literal: true

require "rails_helper"

# Cross-tenant isolation contract for ExternalSourcesController.
#
# ExternalSourcesController is fully gated by UserAuthentication
# (require_authentication runs as a before_action on ApplicationController,
# with no skip in this controller), so current_user is guaranteed present
# before #set_email_account runs. #set_email_account previously resolved the
# globally-first active EmailAccount (`EmailAccount.active.order(:id).first`)
# regardless of who was signed in — any authenticated user could view, sync,
# or disconnect another user's linked external budget source. It now scopes
# through `EmailAccount.for_user(current_user)`.
RSpec.describe "ExternalSources data isolation", type: :request, unit: true do
  let!(:user_a) { create(:user) }
  let!(:user_b) { create(:user) }
  # user_a's account is created first so it would be the "globally first active"
  # account under the old unscoped lookup — the isolation bug this spec guards.
  let!(:email_account_a) { create(:email_account, user: user_a, active: true) }
  let!(:external_source_a) { create(:external_budget_source, email_account: email_account_a, active: true) }

  describe "GET /external_source (show)" do
    context "when user_b has no email account of their own" do
      it "does not expose user_a's connected external source" do
        sign_in_as(user_b)

        get external_source_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("external_sources.not_connected"))
        expect(response.body).not_to include(I18n.t("external_sources.sync_now"))
      end
    end

    context "when the owner requests their own source (happy path)" do
      it "shows user_a's connected state" do
        sign_in_as(user_a)

        get external_source_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("external_sources.sync_now"))
      end
    end
  end

  describe "POST /external_source/sync_now" do
    it "does not let user_b trigger a sync of user_a's external source" do
      sign_in_as(user_b)

      expect {
        post sync_now_external_source_path
      }.not_to have_enqueued_job(ExternalBudgets::PullJob)

      expect(response).to redirect_to(external_source_path)
      expect(flash[:alert]).to eq(I18n.t("external_sources.not_connected"))
    end
  end

  describe "DELETE /external_source" do
    it "does not let user_b disconnect user_a's external source" do
      sign_in_as(user_b)

      expect {
        delete external_source_path
      }.not_to change { ExternalBudgetSource.count }

      expect(external_source_a.reload).to be_active
    end
  end
end
