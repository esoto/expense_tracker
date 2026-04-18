# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "ExternalSources", type: :request do
  let(:base_url) { "https://salary-calc.estebansoto.dev" }
  let!(:admin_user) { create(:admin_user) }

  # Use the :test queue adapter so `have_enqueued_job` works. The global
  # unit-test helper stubs `perform_later` on ActiveJob::Base *instances*
  # (`allow_any_instance_of(ActiveJob::Base).to receive(:perform_later)`),
  # which normally has no effect on our `Klass.perform_later(...)` calls
  # (those are class-method calls). We keep the adapter explicit for safety.
  before do
    ActiveJob::Base.queue_adapter = :test
    sign_in_admin(admin_user)
  end

  describe "GET /external_source" do
    context "when no external source is linked" do
      before { create(:email_account) }

      it "renders the 'not connected' state with a Connect CTA" do
        get external_source_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("external_sources.not_connected"))
        expect(response.body).to include(connect_external_source_path)
      end
    end

    context "when an active source is present" do
      let!(:account) { create(:email_account) }
      let!(:source) do
        create(:external_budget_source, email_account: account, active: true, last_synced_at: 5.minutes.ago)
      end

      it "renders the 'connected' state with Sync now and Disconnect actions" do
        get external_source_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("external_sources.sync_now"))
        expect(response.body).to include(I18n.t("external_sources.disconnect"))
        expect(response.body).to include(sync_now_external_source_path)
      end
    end

    context "when an inactive source is present" do
      let!(:account) { create(:email_account) }
      let!(:source) { create(:external_budget_source, email_account: account, active: false) }

      it "renders the 'reconnect required' banner" do
        get external_source_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("external_sources.reconnect_required"))
        expect(response.body).to match(/bg-amber-|text-amber-|border-amber-/)
      end
    end
  end

  describe "POST /external_source/connect" do
    context "when no email account exists" do
      it "redirects to email_accounts_path with an alert" do
        post connect_external_source_path
        expect(response).to redirect_to(email_accounts_path)
        expect(flash[:alert]).to eq(I18n.t("external_sources.no_account"))
      end
    end

    context "when an active email account exists" do
      let!(:account) { create(:email_account, active: true) }

      it "stores state in the session and redirects to the authorize URL" do
        post connect_external_source_path
        expect(response).to have_http_status(:redirect)
        expect(response.location).to match(%r{\Ahttps://salary-calc\.estebansoto\.dev/oauth/authorize\?})

        query = Rack::Utils.parse_query(URI.parse(response.location).query)
        expect(query.keys).to include("redirect_uri", "state", "scopes")
        expect(query["scopes"]).to eq("budget:read")

        stored = session[:external_oauth_state]
        expect(stored).to be_present
        expect(stored["state"]).to eq(query["state"])
        expect(stored["email_account_id"]).to eq(account.id)
        expect(Time.zone.parse(stored["expires_at"])).to be > Time.current
      end
    end
  end

  describe "GET /external_source/callback" do
    let!(:account) { create(:email_account, active: true) }

    context "with missing state in session" do
      it "redirects with an alert" do
        get callback_external_source_path, params: { state: "anything", code: "xyz" }
        expect(response).to redirect_to(external_source_path)
        expect(flash[:alert]).to eq(I18n.t("external_sources.state_mismatch"))
      end
    end

    context "with mismatched state" do
      it "redirects with an alert" do
        post connect_external_source_path # sets session state
        get callback_external_source_path, params: { state: "wrong-state", code: "xyz" }
        expect(response).to redirect_to(external_source_path)
        expect(flash[:alert]).to eq(I18n.t("external_sources.state_mismatch"))
      end
    end

    context "with expired state" do
      it "redirects with an alert" do
        post connect_external_source_path
        stored = session[:external_oauth_state]
        # Force expiry by traveling past the stored window.
        travel_to(Time.zone.parse(stored["expires_at"]) + 1.minute) do
          get callback_external_source_path, params: { state: stored["state"], code: "xyz" }
        end
        expect(response).to redirect_to(external_source_path)
        expect(flash[:alert]).to eq(I18n.t("external_sources.state_expired"))
      end
    end

    context "with valid state and successful token exchange" do
      before do
        allow_any_instance_of(Services::Oauth::TokenExchanger)
          .to receive(:call).and_return(
            access_token: "tok123", token_type: "Bearer", scope: "budget:read"
          )
      end

      it "creates the external source, enqueues PullJob, and redirects with notice" do
        post connect_external_source_path
        stored = session[:external_oauth_state]

        expect {
          get callback_external_source_path, params: { state: stored["state"], code: "auth-code-1" }
        }.to change { ExternalBudgetSource.count }.by(1)
          .and have_enqueued_job(ExternalBudgets::PullJob)

        expect(response).to redirect_to(external_source_path)
        expect(flash[:notice]).to eq(I18n.t("external_sources.connected"))

        source = ExternalBudgetSource.last
        expect(source.email_account_id).to eq(account.id)
        expect(source.source_type).to eq("salary_calculator")
        expect(source.api_token).to eq("tok123")
        expect(source.active).to be(true)
      end
    end

    context "with an existing inactive source (reconnect flow)" do
      before do
        allow_any_instance_of(Services::Oauth::TokenExchanger)
          .to receive(:call).and_return(access_token: "tok-new", token_type: "Bearer", scope: "budget:read")
      end

      it "updates the existing source in place and reactivates it" do
        existing = create(:external_budget_source,
                          email_account: account,
                          api_token: "tok-old",
                          active: false,
                          last_sync_error: "previous failure")

        post connect_external_source_path
        stored = session[:external_oauth_state]

        expect {
          get callback_external_source_path, params: { state: stored["state"], code: "auth-code-reconnect" }
        }.not_to change { ExternalBudgetSource.count }

        existing.reload
        expect(existing.api_token).to eq("tok-new")
        expect(existing.active).to be(true)
        expect(existing.last_sync_error).to be_nil
        expect(response).to redirect_to(external_source_path)
        expect(flash[:notice]).to eq(I18n.t("external_sources.connected"))
      end
    end

    context "when token exchange fails" do
      before do
        allow_any_instance_of(Services::Oauth::TokenExchanger)
          .to receive(:call).and_raise(Services::Oauth::TokenExchanger::Error.new("boom"))
      end

      it "does not create a source and redirects with an alert" do
        post connect_external_source_path
        stored = session[:external_oauth_state]

        expect {
          get callback_external_source_path, params: { state: stored["state"], code: "x" }
        }.not_to change { ExternalBudgetSource.count }

        expect(response).to redirect_to(external_source_path)
        expect(flash[:alert]).to eq(I18n.t("external_sources.exchange_failed"))
      end
    end
  end

  describe "POST /external_source/sync_now" do
    let!(:account) { create(:email_account, active: true) }
    let!(:source) { create(:external_budget_source, email_account: account, active: true) }

    it "enqueues PullJob and redirects with a notice" do
      expect {
        post sync_now_external_source_path
      }.to have_enqueued_job(ExternalBudgets::PullJob).with(source.id)

      expect(response).to redirect_to(external_source_path)
      expect(flash[:notice]).to eq(I18n.t("external_sources.sync_queued"))
    end
  end

  describe "DELETE /external_source" do
    let!(:account) { create(:email_account, active: true) }
    let!(:source) { create(:external_budget_source, email_account: account, active: true) }

    it "destroys the source and redirects with a notice" do
      expect { delete external_source_path }.to change { ExternalBudgetSource.count }.by(-1)
      expect(response).to redirect_to(external_source_path)
      expect(flash[:notice]).to eq(I18n.t("external_sources.disconnected"))
    end
  end
end
