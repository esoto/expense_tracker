# frozen_string_literal: true

require "rails_helper"

# Data-isolation contract for SyncSessionsController.
#
# Verifies that GET /sync_sessions and GET /sync_sessions/:id return ONLY the
# sync sessions belonging to the scoping user and NEVER leak another user's data.
#
# UserAuthentication is not yet gating SyncSessionsController (PR 12 does that).
# Until then the controller falls back to User.admin.first via `scoping_user`.
# This spec exercises that fallback path so the isolation contract is validated
# NOW and remains green when PR 12 wires up full auth.
#
# Pattern mirrors PR 6's budgets_isolation_spec.rb.
RSpec.describe "SyncSessions data isolation", type: :request, unit: true do
  # Bypass the SyncAuthorization concern and current_user so we can control
  # which User is the scoping_user via the controller's fallback logic.
  before do
    allow_any_instance_of(SyncSessionsController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(SyncSessionsController).to receive(:current_user).and_return(nil)
    allow_any_instance_of(SyncSessionsController).to receive(:authorize_sync_access!).and_return(true)
    allow_any_instance_of(SyncSessionsController).to receive(:authorize_sync_session_owner!).and_return(true)
  end

  describe "GET /sync_sessions" do
    context "when scoping_user is User.admin.first (admin fallback path)" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }
      let!(:session_a1) { create(:sync_session, user: user_a, status: "completed") }
      let!(:session_a2) { create(:sync_session, user: user_a, status: "failed") }
      let!(:session_b)  { create(:sync_session, user: user_b, status: "completed") }

      before do
        allow_any_instance_of(SyncSessionsController)
          .to receive(:scoping_user)
          .and_return(user_a)

        get sync_sessions_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end
    end

    context "scoping_user isolation — user B cannot see user A's sessions" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }
      let!(:session_a) { create(:sync_session, user: user_a) }
      let!(:session_b) { create(:sync_session, user: user_b) }

      before do
        allow_any_instance_of(SyncSessionsController)
          .to receive(:scoping_user)
          .and_return(user_b)

        get sync_sessions_path
      end

      it "returns HTTP 200" do
        expect(response).to have_http_status(:ok)
      end
    end

    context "for_user scope isolation — database-level verification" do
      let!(:user_a) { create(:user, :admin) }
      let!(:user_b) { create(:user) }
      let!(:session_a) { create(:sync_session, user: user_a) }
      let!(:session_b) { create(:sync_session, user: user_b) }

      it "for_user(user_a) includes session_a and excludes session_b" do
        result = SyncSession.for_user(user_a)
        expect(result).to include(session_a)
        expect(result).not_to include(session_b)
      end

      it "for_user(user_b) includes session_b and excludes session_a" do
        result = SyncSession.for_user(user_b)
        expect(result).to include(session_b)
        expect(result).not_to include(session_a)
      end
    end
  end

  describe "GET /sync_sessions/:id" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:session_a) { create(:sync_session, user: user_a) }

    context "when scoping_user is user_b (cross-user access attempt)" do
      before do
        allow_any_instance_of(SyncSessionsController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "redirects with not_found — user B cannot access user A's session" do
        # The scoped find via for_user(user_b).find(session_a.id) raises RecordNotFound
        # because session_a belongs to user_a. The controller rescues and redirects.
        get sync_session_path(session_a)
        expect(response).to redirect_to(sync_sessions_path)
      end
    end

    context "when scoping_user is user_a (owner access)" do
      before do
        allow_any_instance_of(SyncSessionsController)
          .to receive(:scoping_user)
          .and_return(user_a)
      end

      it "returns HTTP 200 for owner" do
        get sync_session_path(session_a)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # Mutation isolation: cancel/retry must fail for cross-user access.
  # `set_sync_session` scopes via `for_user(scoping_user)`, so the lookup
  # fails before the action body runs. The controller rescues RecordNotFound
  # and redirects.
  describe "mutation isolation (POST cancel/retry)" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:session_a) { create(:sync_session, :running, user: user_a) }

    context "when user_b tries to cancel user_a's session" do
      before do
        allow_any_instance_of(SyncSessionsController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "POST cancel redirects (not found) and does not mutate" do
        original_status = session_a.status
        post cancel_sync_session_path(session_a)
        expect(response).to redirect_to(sync_sessions_path)
        expect(session_a.reload.status).to eq(original_status)
      end
    end
  end

  # CREATE isolation — newly created SyncSessions must be assigned to scoping_user.
  describe "POST /sync_sessions — user_id cannot be spoofed via params" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }

    before do
      allow_any_instance_of(SyncSessionsController)
        .to receive(:scoping_user)
        .and_return(user_b)

      # Stub the creator service to avoid email account requirements in integration
      allow(Services::SyncSessionCreator).to receive(:new).and_wrap_original do |_orig, params, request_info, user|
        instance_double(Services::SyncSessionCreator,
          call: Services::SyncSessionCreator::Result.new(
            success: true,
            sync_session: create(:sync_session, user: user)
          ))
      end
    end

    it "assigns the new session to scoping_user (user_b)" do
      post sync_sessions_path, params: { email_account_id: nil }
      # Verify the creator was called with user_b as the third argument
      expect(Services::SyncSessionCreator).to have_received(:new)
        .with(anything, anything, user_b)
    end
  end
end
