require 'rails_helper'

RSpec.describe "email_accounts/show", type: :view, unit: true do
  let(:email_account) do
    build_stubbed(:email_account,
      email: "user@example.com",
      bank_name: "BAC San José",
      provider: "custom",
      active: true
    )
  end

  before do
    assign(:email_account, email_account)
    allow(email_account).to receive(:imap_settings).and_return({ address: "imap.example.com", port: 993 })
    allow(view).to receive(:edit_email_account_path).and_return("/email_accounts/1/edit")
    allow(view).to receive(:email_accounts_path).and_return("/email_accounts")
  end

  context "with a custom provider" do
    it "displays the translated provider name in Spanish" do
      render
      expect(rendered).to have_content("Personalizado")
    end

    it "does not display the raw English 'Custom'" do
      render
      expect(rendered).not_to have_content("Custom")
    end
  end

  context "with a gmail provider" do
    let(:email_account) do
      build_stubbed(:email_account,
        email: "user@gmail.com",
        bank_name: "BAC San José",
        provider: "gmail",
        active: true
      )
    end

    it "displays Gmail as the provider name" do
      render
      expect(rendered).to have_content("Gmail")
    end
  end

  context "with an outlook provider" do
    let(:email_account) do
      build_stubbed(:email_account,
        email: "user@outlook.com",
        bank_name: "BAC San José",
        provider: "outlook",
        active: true
      )
    end

    it "displays Outlook as the provider name" do
      render
      expect(rendered).to have_content("Outlook")
    end
  end
end
