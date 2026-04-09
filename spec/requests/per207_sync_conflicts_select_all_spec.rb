# frozen_string_literal: true

require "rails_helper"

# PER-207: Verify the page structure that enables "Seleccionar todo" to reach
# row checkboxes via the bulk-actions Stimulus controller.
#
# Root cause: data-controller="bulk-actions" was scoped to the toolbar <div>
# only, so checkboxTargets and selectAllTarget in the <table> were outside
# the controller scope and therefore invisible to the selectAll action.
#
# Fix: the controller attribute is now on an outer wrapper <div> that contains
# both the toolbar and the conflicts table.
RSpec.describe "SyncConflicts select-all page structure", type: :request, unit: true do
  let(:admin_user) do
    AdminUser.create!(
      name: "PER-207 Test Admin",
      email: "per207-admin-#{SecureRandom.hex(4)}@test.com",
      password: "AdminPassword123!",
      role: "admin"
    )
  end

  let(:sync_session) { create(:sync_session, :completed) }

  # A bulk-resolvable pending conflict renders a row checkbox.
  let!(:bulk_conflict) do
    create(
      :sync_conflict,
      sync_session: sync_session,
      status: "pending",
      bulk_resolvable: true,
      conflict_type: "similar"
    )
  end

  # A non-bulk-resolvable conflict renders no checkbox (control case).
  let!(:non_bulk_conflict) do
    create(
      :sync_conflict,
      sync_session: sync_session,
      status: "pending",
      bulk_resolvable: false,
      conflict_type: "needs_review"
    )
  end

  before { sign_in_admin(admin_user) }

  describe "GET /sync_conflicts" do
    before { get sync_conflicts_path }

    it "returns HTTP 200" do
      expect(response).to have_http_status(:ok)
    end

    # The outer wrapper must carry data-controller="bulk-actions" so that
    # both the toolbar buttons and the table row checkboxes live inside the
    # same Stimulus controller scope.
    it "has a single bulk-actions controller on an ancestor element that wraps " \
       "both the toolbar and the table" do
      body = response.body

      # Exactly one element should declare the controller.
      controller_occurrences = body.scan('data-controller="bulk-actions"').size
      expect(controller_occurrences).to eq(1),
        "Expected exactly 1 data-controller=\"bulk-actions\" but found #{controller_occurrences}. " \
        "The controller must be on a wrapper that contains both the toolbar and the table."
    end

    it "renders the select-all button inside the bulk-actions controller scope" do
      body = response.body
      controller_open_pos = body.index('data-controller="bulk-actions"')
      select_all_btn_pos  = body.index('Seleccionar todo')

      expect(controller_open_pos).to be_present
      expect(select_all_btn_pos).to be_present
      expect(select_all_btn_pos).to be > controller_open_pos
    end

    it "renders the header selectAll checkbox inside the bulk-actions controller scope" do
      body = response.body
      controller_open_pos   = body.index('data-controller="bulk-actions"')
      select_all_target_pos = body.index('data-bulk-actions-target="selectAll"')

      expect(controller_open_pos).to be_present
      expect(select_all_target_pos).to be_present
      expect(select_all_target_pos).to be > controller_open_pos
    end

    it "renders a row checkbox for the bulk-resolvable conflict " \
       "inside the bulk-actions controller scope" do
      body = response.body
      controller_open_pos  = body.index('data-controller="bulk-actions"')
      checkbox_target_pos  = body.index('data-bulk-actions-target="checkbox"')

      expect(controller_open_pos).to be_present
      expect(checkbox_target_pos).to be_present,
        "Expected a data-bulk-actions-target=\"checkbox\" for the bulk-resolvable conflict"
      expect(checkbox_target_pos).to be > controller_open_pos
    end

    it "does not render a row checkbox for the non-bulk-resolvable conflict" do
      # Only one checkbox target should be present (the one bulk-resolvable row).
      # If the non-bulk conflict incorrectly rendered a checkbox, the count would be 2.
      checkbox_count = response.body.scan('data-bulk-actions-target="checkbox"').size
      expect(checkbox_count).to eq(1),
        "Expected exactly 1 row checkbox (for the bulk-resolvable conflict) but found #{checkbox_count}"
    end

    it "places the select-all button and the row checkbox in the same controller scope" do
      body = response.body
      controller_open_pos  = body.index('data-controller="bulk-actions"')
      select_all_btn_pos   = body.index('Seleccionar todo')
      checkbox_target_pos  = body.index('data-bulk-actions-target="checkbox"')

      # Both must exist and appear after the controller declaration.
      expect(select_all_btn_pos).to be  > controller_open_pos
      expect(checkbox_target_pos).to be > controller_open_pos
    end
  end
end
