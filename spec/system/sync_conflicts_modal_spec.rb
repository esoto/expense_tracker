require "rails_helper"

# Regression coverage for the sync-conflict resolution modal overlay bug:
# the backdrop (position: fixed, z-index: auto) used to paint ABOVE the
# static-positioned modal panel per CSS stacking rules, silently swallowing
# every click on the panel (buttons, close icon, cancel). Verified via
# Playwright: `document.elementFromPoint` at "Mantener Existente" resolved to
# the backdrop div, not the button, so clicks there timed out and 0 of 75
# pending conflicts were ever resolved in production.
#
# This spec drives the real browser (Selenium/Chrome headless) so it exercises
# actual pointer-event hit-testing, which a rack_test / request spec cannot.
RSpec.describe "Sync conflict resolution modal", type: :system, js: true, tier: :system do
  let(:admin_user) { create(:user, :admin) }
  let(:sync_session) { create(:sync_session, user: admin_user) }
  let(:existing_expense) { create(:expense, amount: 100.00, merchant_name: "Original Store") }
  let(:new_expense) { create(:expense, amount: 150.00, merchant_name: "Updated Store") }

  let!(:sync_conflict) do
    create(:sync_conflict,
           sync_session: sync_session,
           user: admin_user,
           existing_expense: existing_expense,
           new_expense: new_expense,
           status: "pending",
           conflict_type: "duplicate")
  end

  before do
    sign_in_admin_user(admin_user)
    visit sync_conflicts_path
  end

  def open_modal
    within "#conflict_#{sync_conflict.id}" do
      click_link_or_button "Resolver"
    end
    expect(page).to have_css("#conflict_modal_content", wait: 5)
  end

  it "clicking the backdrop closes the modal without resolving anything" do
    open_modal

    # Click near the top-left corner of the full-viewport backdrop, well
    # outside the centered panel, so we genuinely hit the backdrop element
    # instead of Selenium clicking through to the panel underneath it.
    find('[data-action="click->conflict-modal#closeOnBackdropClick"]').click(x: 5, y: 5)

    expect(page).to have_no_css("#conflict_modal_content")
    expect(sync_conflict.reload.status).to eq("pending")
  end

  it "clicking a panel button never closes the modal via the backdrop handler" do
    open_modal

    # A click on real panel content (the header) must not bubble into a
    # modal close — this is the "e.target === e.currentTarget" contract.
    find("h3", text: "Resolver Conflicto de Sincronización").click

    expect(page).to have_css("#conflict_modal_content")
  end

  it "resolving a conflict closes the modal and updates the row" do
    open_modal

    # This is the exact click that used to time out in production: the
    # backdrop overlay previously intercepted every pointer event here.
    click_button "Mantener Existente"

    expect(page).to have_content("Resuelto", wait: 5)
    expect(page).to have_no_css("#conflict_modal_content")
    expect(sync_conflict.reload.status).to eq("resolved")
  end

  it "pressing Escape closes the open modal" do
    open_modal

    find("body").send_keys(:escape)

    expect(page).to have_no_css("#conflict_modal_content")
  end
end
