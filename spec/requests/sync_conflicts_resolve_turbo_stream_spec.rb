# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the sync-conflict resolution modal fix (PER conflict
# modal overlay bug): the modal's Stimulus controller decides whether to close
# on `turbo:submit-end` by reading `event.detail.success`, which Turbo derives
# from the response HTTP status. The controller previously rendered the
# turbo_stream failure branch with an implicit 200 OK, which would have made
# a failed resolution look like a success to the frontend and close the modal
# on error. This spec locks in the status codes both branches must return.
RSpec.describe "SyncConflicts#resolve turbo_stream response", type: :request, unit: true do
  let(:admin_user) { create(:user, :admin) }
  let(:sync_session) { create(:sync_session, user: admin_user) }
  let(:existing_expense) { create(:expense, amount: 100.00, merchant_name: "Original Store") }
  let(:new_expense) { create(:expense, amount: 150.00, merchant_name: "Updated Store") }
  let(:sync_conflict) do
    create(:sync_conflict,
           sync_session: sync_session,
           user: admin_user,
           existing_expense: existing_expense,
           new_expense: new_expense,
           status: "pending",
           conflict_type: "duplicate")
  end

  before do
    allow_any_instance_of(SyncConflictsController).to receive(:require_authentication).and_return(true)
    allow_any_instance_of(SyncConflictsController).to receive(:current_user).and_return(nil)
    allow_any_instance_of(SyncConflictsController).to receive(:scoping_user).and_return(admin_user)
  end

  def turbo_stream_headers
    { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  context "when the resolution succeeds" do
    it "returns 200 so the frontend can safely close the modal" do
      post resolve_sync_conflict_path(sync_conflict),
           params: { action_type: "keep_existing" },
           headers: turbo_stream_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    end

    it "replaces the conflict row and prepends a success toast" do
      post resolve_sync_conflict_path(sync_conflict),
           params: { action_type: "keep_existing" },
           headers: turbo_stream_headers

      expect(response.body).to include("conflict_#{sync_conflict.id}")
      expect(response.body).to include("Conflicto resuelto exitosamente")
    end
  end

  context "when the resolution fails" do
    it "returns 422 so the frontend keeps the modal open for the user to see the error" do
      post resolve_sync_conflict_path(sync_conflict),
           params: { action_type: "not_a_real_action" },
           headers: turbo_stream_headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "prepends an error toast" do
      post resolve_sync_conflict_path(sync_conflict),
           params: { action_type: "not_a_real_action" },
           headers: turbo_stream_headers

      expect(response.body).to include("bg-rose-50")
    end
  end

  # This repo's system specs require a real JS-capable browser (Selenium +
  # Chrome), which isn't available in this environment (no chromedriver /
  # Chrome binary, and the shared `sign_in_admin_user` system-spec helper is
  # currently broken independent of this fix — see limitation note below).
  # A `spec/system/sync_conflicts_modal_spec.rb` was still added for CI
  # environments where the browser driver *is* available; here we lock in the
  # markup contract at the request layer, which is exercisable everywhere.
  describe "GET show (modal partial markup)" do
    it "gives the panel a higher stacking layer than the backdrop" do
      get sync_conflict_path(sync_conflict),
          headers: { "X-Requested-With" => "XMLHttpRequest", "Accept" => "text/html" }

      expect(response.body).to include('data-action="click->conflict-modal#closeOnBackdropClick"')
      expect(response.body).to include("relative z-10 inline-block")
    end
  end
end
