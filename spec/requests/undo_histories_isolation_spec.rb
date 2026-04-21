# frozen_string_literal: true

require "rails_helper"

# Data-isolation contract for UndoHistoriesController.
#
# Verifies that POST /undo_histories/:id/undo only operates on the undo history
# entry belonging to the scoping_user and NEVER allows cross-user mutation.
#
# UserAuthentication is not yet gating UndoHistoriesController (PR 12 does that).
# Until then the controller falls back to User.admin.first via `scoping_user`.
# This spec exercises that fallback path so the isolation contract is validated
# NOW and remains green when PR 12 wires up full auth.
#
# Pattern mirrors PR 7's sync_sessions_isolation_spec.rb.
RSpec.describe "UndoHistories data isolation", type: :request, unit: true do
  # Bypass authentication so we can control which User is the scoping_user.
  before do
    allow_any_instance_of(UndoHistoriesController)
      .to receive(:require_authentication)
      .and_return(true)
    allow_any_instance_of(UndoHistoriesController)
      .to receive(:current_user)
      .and_return(nil)
  end

  describe "for_user scope isolation — database-level verification" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:history_a) { create(:undo_history, user: user_a) }
    let!(:history_b) { create(:undo_history, user: user_b) }

    it "for_user(user_a) includes history_a and excludes history_b" do
      result = UndoHistory.for_user(user_a)
      expect(result).to include(history_a)
      expect(result).not_to include(history_b)
    end

    it "for_user(user_b) includes history_b and excludes history_a" do
      result = UndoHistory.for_user(user_b)
      expect(result).to include(history_b)
      expect(result).not_to include(history_a)
    end
  end

  describe "POST /undo_histories/:id/undo — cross-user access blocked" do
    let!(:user_a) { create(:user, :admin) }
    let!(:user_b) { create(:user) }
    let!(:history_a) { create(:undo_history, user: user_a) }

    context "when scoping_user is user_b (cross-user access attempt)" do
      before do
        allow_any_instance_of(UndoHistoriesController)
          .to receive(:scoping_user)
          .and_return(user_b)
      end

      it "returns not_found when user_b tries to undo user_a's history" do
        post undo_undo_history_path(history_a), as: :json
        expect(response).to have_http_status(:not_found)
      end

      it "does not mutate the undo history record" do
        original_undone_at = history_a.undone_at
        post undo_undo_history_path(history_a), as: :json
        expect(history_a.reload.undone_at).to eq(original_undone_at)
      end
    end

    context "when scoping_user is user_a (owner access)" do
      before do
        allow_any_instance_of(UndoHistoriesController)
          .to receive(:scoping_user)
          .and_return(user_a)
      end

      it "finds the record (does not return not_found)" do
        # undo! may return false if the record is not undoable, but it should NOT
        # return 404 — that would mean the scoping failed.
        post undo_undo_history_path(history_a), as: :json
        expect(response).not_to have_http_status(:not_found)
      end
    end
  end
end
