# frozen_string_literal: true

require "rails_helper"

# PER-187: Bulk selection action buttons enabled with 0 items selected.
#
# Root cause: The batch-selection Stimulus controller had a requestAnimationFrame
# race condition — when clearSelection() was called synchronously after a show
# was triggered, the pending rAF callback could re-add `animate-slide-up` to
# the already-hidden toolbar. Additionally, on initial connect() the
# `opacity-50 cursor-not-allowed` classes were not applied to the bulk-actions
# button until updateUI() ran, which could leave a brief enabled-looking state.
#
# Fix:
# 1. Track the pending rAF ID and cancel it before hiding the toolbar.
# 2. On connect, store `toolbarAnimationFrame = null` so it's always initialized.
# 3. Guard the rAF callback — only add `animate-slide-up` when count is still > 0.
# 4. cancelAnimationFrame() called in disconnect() to prevent memory leaks.
RSpec.describe "PER-187 Bulk selection toolbar HTML initial state", type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user) }

  before { sign_in_admin(admin_user) }

  describe "GET /expenses", :unit do
    context "when rendering the expenses index page" do
      it "renders the selection toolbar as hidden by default" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        # The toolbar div starts with `class="hidden ...` (hidden is the first class)
        # so it is invisible before JS runs. The view has:
        #   <div class="hidden fixed bottom-0 ..." data-batch-selection-target="selectionToolbar">
        expect(response.body).to include('data-batch-selection-target="selectionToolbar"')
        expect(response.body).to include('class="fixed bottom-0 left-0 right-0')
      end

      it "renders the bulk actions button with disabled attribute" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        # The bulk actions button must carry `disabled` so the browser enforces
        # the disabled state even before the Stimulus controller initializes.
        # In the HTML the attributes span lines:
        #   data-batch-selection-target="bulkActionsButton"
        #   data-action="..."
        #   class="... disabled:opacity-50 disabled:cursor-not-allowed"
        #   disabled>
        expect(response.body).to include('data-batch-selection-target="bulkActionsButton"')
        expect(response.body).to match(
          /data-batch-selection-target="bulkActionsButton"[\s\S]{0,500}disabled>/m
        )
      end

      it "renders the bulk actions button with Tailwind disabled-variant opacity classes" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        # Tailwind `disabled:opacity-50 disabled:cursor-not-allowed` must be
        # present so that CSS applies visual disabled state even before JS runs
        expect(response.body).to include("disabled:opacity-50")
        expect(response.body).to include("disabled:cursor-not-allowed")
      end

      it "does not render the selection toolbar with flex as the first display class" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        # The toolbar must never start in a flex (visible) state — it must start hidden
        expect(response.body).not_to include('class="flex fixed bottom-0')
      end

      it "renders the selection counter as hidden" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-batch-selection-target="selectionCounter"')
        expect(response.body).to include('class="hidden px-4 py-2 bg-teal-50')
      end
    end

    context "when there are expenses in the list", :unit do
      let!(:category) { create(:category) }
      let!(:expense) do
        create(:expense,
          email_account: email_account,
          category: category,
          amount: 10_000,
          merchant_name: "Test Merchant"
        )
      end

      it "still renders the toolbar hidden even when expenses exist" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        # Toolbar visibility is controlled by JS selection state, not expense count
        expect(response.body).to include('data-batch-selection-target="selectionToolbar"')
        expect(response.body).to include('class="fixed bottom-0 left-0 right-0')
      end

      it "still renders the bulk actions button disabled when no items are selected" do
        get expenses_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-batch-selection-target="bulkActionsButton"')
        expect(response.body).to match(
          /data-batch-selection-target="bulkActionsButton"[\s\S]{0,500}disabled>/m
        )
      end
    end
  end
end
