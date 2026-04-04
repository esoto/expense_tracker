require 'rails_helper'

RSpec.describe "sync_sessions/show", type: :view, unit: true do
  around { |example| I18n.with_locale(:es) { example.run } }

  let(:email_account) { build_stubbed(:email_account, email: "user@example.com", bank_name: "BAC") }

  let(:session_account) do
    build_stubbed(:sync_session_account,
      email_account: email_account,
      status: "completed",
      total_emails: 100,
      processed_emails: 100,
      detected_expenses: 10,
      last_error: nil
    )
  end

  before do
    allow(view).to receive(:sync_sessions_path).and_return("/sync_sessions")
    allow(view).to receive(:cancel_sync_session_path).and_return("/sync_sessions/1/cancel")
    allow(view).to receive(:retry_sync_session_path).and_return("/sync_sessions/1/retry")

    accounts_relation = double("session_accounts")
    allow(accounts_relation).to receive(:includes).with(:email_account).and_return([ session_account ])
    allow(accounts_relation).to receive(:count).and_return(1)
    assign(:session_accounts, accounts_relation)
  end

  context "with a completed sync session" do
    let(:sync_session) { build_stubbed(:sync_session, :completed, id: 1) }

    before { assign(:sync_session, sync_session) }

    it "displays 'Completado' for session status" do
      render
      expect(rendered).to have_content("Completado")
    end

    it "does not display English 'Completed'" do
      render
      expect(rendered).not_to have_content(/\bCompleted\b/)
    end
  end

  context "with a failed sync session" do
    let(:sync_session) { build_stubbed(:sync_session, :failed, id: 2) }

    before { assign(:sync_session, sync_session) }

    it "displays 'Fallido' for session status" do
      render
      expect(rendered).to have_content("Fallido")
    end
  end

  context "with a cancelled sync session" do
    let(:sync_session) { build_stubbed(:sync_session, :cancelled, id: 3) }

    before do
      assign(:sync_session, sync_session)
      allow(view).to receive(:retry_sync_session_path).with(sync_session).and_return("/sync_sessions/3/retry")
    end

    it "displays 'Cancelado' for session status" do
      render
      expect(rendered).to have_content("Cancelado")
    end
  end

  context "with a pending sync session" do
    let(:sync_session) { build_stubbed(:sync_session, id: 4) }

    before { assign(:sync_session, sync_session) }

    it "displays 'Pendiente' for pending session status" do
      render
      expect(rendered).to have_content("Pendiente")
    end
  end

  context "account status translation" do
    let(:completed_account) do
      build_stubbed(:sync_session_account,
        email_account: email_account,
        status: "completed",
        total_emails: 100,
        processed_emails: 100,
        detected_expenses: 5,
        last_error: nil
      )
    end

    let(:sync_session) { build_stubbed(:sync_session, :completed, id: 1) }

    before do
      assign(:sync_session, sync_session)
      accounts_relation = double("session_accounts")
      allow(accounts_relation).to receive(:includes).with(:email_account).and_return([ completed_account ])
      allow(accounts_relation).to receive(:count).and_return(1)
      assign(:session_accounts, accounts_relation)
    end

    it "does not display raw English account status" do
      render
      expect(rendered).to have_content("Completado")
      expect(rendered).not_to have_content(/\bCompleted\b/)
    end
  end
end
