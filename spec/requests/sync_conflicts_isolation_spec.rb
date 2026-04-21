# frozen_string_literal: true

require "rails_helper"

# Data-isolation contract for SyncConflictsController.
#
# This spec verifies that sync_conflicts queries never leak across users.
# UserAuthentication is not yet gating this controller (PR 12 does that);
# until then the controller uses `scoping_user` with an admin-fallback.
#
# Mirrors the spec/requests/sync_sessions_isolation_spec pattern.
RSpec.describe "SyncConflicts data isolation", type: :request, unit: true do
  before do
    allow_any_instance_of(SyncConflictsController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(SyncConflictsController).to receive(:current_user).and_return(nil)
  end

  describe "GET /sync_conflicts (index)" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:session_a) { create(:sync_session, user: user_a) }
    let!(:session_b) { create(:sync_session, user: user_b) }
    let!(:conflict_a1) { create(:sync_conflict, sync_session: session_a, user: user_a) }
    let!(:conflict_a2) { create(:sync_conflict, sync_session: session_a, user: user_a) }
    let!(:conflict_b)  { create(:sync_conflict, sync_session: session_b, user: user_b) }

    context "when scoping_user is user_a" do
      before do
        allow_any_instance_of(SyncConflictsController)
          .to receive(:scoping_user).and_return(user_a)
        get sync_conflicts_path
      end

      it "returns 200" do
        expect(response).to have_http_status(:ok)
      end

      it "excludes user_b's conflict from the response" do
        expect(response.body).not_to include("conflict_#{conflict_b.id}")
      end
    end

    context "when scoping_user is user_b (cross-user)" do
      before do
        allow_any_instance_of(SyncConflictsController)
          .to receive(:scoping_user).and_return(user_b)
        get sync_conflicts_path
      end

      it "does not include user_a's conflicts" do
        expect(response.body).not_to include("conflict_#{conflict_a1.id}")
        expect(response.body).not_to include("conflict_#{conflict_a2.id}")
      end
    end
  end

  describe "GET /sync_conflicts/:id (show)" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:session_a) { create(:sync_session, user: user_a) }
    let!(:conflict_a) { create(:sync_conflict, sync_session: session_a, user: user_a) }

    context "when user_b tries to view user_a's conflict" do
      before do
        allow_any_instance_of(SyncConflictsController)
          .to receive(:scoping_user).and_return(user_b)
      end

      it "returns 404 (scoped find fails, request spec renders not_found)" do
        get sync_conflict_path(conflict_a)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /sync_conflicts/:id/resolve" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:session_a) { create(:sync_session, user: user_a) }
    let!(:conflict_a) { create(:sync_conflict, sync_session: session_a, user: user_a) }
    let(:original_status) { conflict_a.status }

    context "when user_b tries to resolve user_a's conflict" do
      before do
        allow_any_instance_of(SyncConflictsController)
          .to receive(:scoping_user).and_return(user_b)
      end

      it "returns 404 and does not mutate the conflict" do
        post resolve_sync_conflict_path(conflict_a),
          params: { action_type: "keep_existing" }
        expect(response).to have_http_status(:not_found)
        expect(conflict_a.reload.status).to eq(original_status)
      end
    end
  end

  describe "POST /sync_conflicts/bulk_resolve" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:session_a) { create(:sync_session, user: user_a) }
    let!(:session_b) { create(:sync_session, user: user_b) }
    let!(:conflict_a) { create(:sync_conflict, sync_session: session_a, user: user_a) }
    let!(:conflict_b) { create(:sync_conflict, sync_session: session_b, user: user_b) }

    context "when user_a submits a mixed list of own and user_b's conflicts" do
      before do
        allow_any_instance_of(SyncConflictsController)
          .to receive(:scoping_user).and_return(user_a)
      end

      it "only the owned conflict is resolvable; cross-user id is silently dropped" do
        # scoped_ids filter in the controller ensures user_b's id is excluded
        # from the service call. user_b's conflict must remain untouched.
        post bulk_resolve_sync_conflicts_path,
          params: { conflict_ids: [ conflict_a.id, conflict_b.id ], action_type: "keep_existing" },
          as: :json
        expect(response).to have_http_status(:ok)
        expect(conflict_b.reload.status).not_to eq("resolved")
      end
    end
  end
end
