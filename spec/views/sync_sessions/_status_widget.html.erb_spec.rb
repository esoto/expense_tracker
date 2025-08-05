require 'rails_helper'

RSpec.describe "sync_sessions/_status_widget", type: :view do
  before do
    # Define the URL helper methods for the view
    allow(view).to receive(:sync_sessions_path).and_return('/sync_sessions')
  end

  context "with an active sync session" do
    let(:active_session) do
      build_stubbed(:sync_session, :running,
        id: 1,
        total_emails: 1000,
        processed_emails: 450,
        detected_expenses: 25,
        started_at: 2.minutes.ago
      )
    end

    let(:email_account1) { build_stubbed(:email_account, email: "personal@example.com", bank_name: "BAC") }
    let(:email_account2) { build_stubbed(:email_account, email: "work@example.com", bank_name: "Mucap") }

    let(:account1) do
      build_stubbed(:sync_session_account,
        sync_session: active_session,
        email_account: email_account1,
        status: 'processing',
        total_emails: 500,
        processed_emails: 250
      )
    end

    let(:account2) do
      build_stubbed(:sync_session_account,
        sync_session: active_session,
        email_account: email_account2,
        status: 'completed',
        total_emails: 500,
        processed_emails: 500
      )
    end

    before do
      assign(:active_sync_session, active_session)
      assign(:last_completed_sync, nil)
      allow(active_session).to receive(:email_accounts).and_return([
        email_account1,
        email_account2
      ])
      # Mock the association to return a collection that responds to includes
      accounts_relation = double("sync_session_accounts")
      allow(accounts_relation).to receive(:includes).with(:email_account).and_return([ account1, account2 ])
      allow(active_session).to receive(:sync_session_accounts).and_return(accounts_relation)
      allow(view).to receive(:sync_session_path).with(active_session).and_return("/sync_sessions/#{active_session.id}")
    end

    it "displays the sync status widget with active session" do
      render

      expect(rendered).to have_content("Estado de Sincronización")
      expect(rendered).to have_link("Ver detalles", href: "/sync_sessions/1")
    end

    it "shows the overall progress" do
      render

      expect(rendered).to have_content("Progreso general")
      expect(rendered).to have_content("45%")
      expect(rendered).to have_css('.bg-teal-700[style*="width: 45%"]')
    end

    it "displays sync statistics" do
      render

      expect(rendered).to have_content("450")
      expect(rendered).to have_content("Correos procesados")
      expect(rendered).to have_content("25")
      expect(rendered).to have_content("Gastos detectados")
      expect(rendered).to have_content("2")
      expect(rendered).to have_content("Cuentas activas")
    end

    it "shows account details with progress" do
      render

      expect(rendered).to have_content("personal@example.com (BAC)")
      expect(rendered).to have_content("50%")
      expect(rendered).to have_content("250 / 500")

      expect(rendered).to have_content("work@example.com (Mucap)")
      expect(rendered).to have_content("100%")
      expect(rendered).to have_content("500 / 500")
    end

    it "displays processing indicator for active accounts" do
      render

      expect(rendered).to have_css('svg.animate-spin')
    end

    it "displays completion indicator for completed accounts" do
      render

      expect(rendered).to have_css('svg path[d*="M5 13l4 4L19 7"]')
    end
  end

  context "without an active sync session" do
    let(:completed_session) do
      build_stubbed(:sync_session, :completed,
        completed_at: 1.hour.ago
      )
    end

    before do
      assign(:active_sync_session, nil)
      assign(:last_completed_sync, completed_session)
    end

    it "displays no active sync message" do
      render

      expect(rendered).to have_content("No hay sincronización activa")
      expect(rendered).to have_link("Ver historial", href: "/sync_sessions")
    end

    it "shows last sync information" do
      render

      expect(rendered).to have_content("Última sincronización:")
      expect(rendered).to have_content("about 1 hour")
    end

    it "provides a button to start new sync" do
      render

      expect(rendered).to have_button("Iniciar sincronización")
    end
  end

  context "without any sync sessions" do
    before do
      assign(:active_sync_session, nil)
      assign(:last_completed_sync, nil)
    end

    it "displays message for no sync history" do
      render

      expect(rendered).to have_content("No se han realizado sincronizaciones")
    end
  end
end
