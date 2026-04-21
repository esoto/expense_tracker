# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ExternalSources flow", type: :system do
  let(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, active: true) }

  before do
    driven_by(:rack_test)
    sign_in_admin_user(admin_user)
  end

  it "shows the not-connected state and exposes a Connect CTA" do
    visit external_source_path
    expect(page).to have_content(I18n.t("external_sources.not_connected"))
    expect(page).to have_button(I18n.t("external_sources.connect"))
  end

  it "redirects to salary_calc/oauth/authorize on Connect" do
    # Drive the request directly via rack-test so we can inspect the 302 without
    # following it off-site (Capybara#visit would silently chase the redirect).
    page.driver.browser.process(:post, connect_external_source_path)

    expect(page.status_code).to eq(302)
    expect(page.response_headers["Location"]).to match(
      %r{\Ahttps://salary-calc\.estebansoto\.dev/oauth/authorize\?}
    )
  end
end
