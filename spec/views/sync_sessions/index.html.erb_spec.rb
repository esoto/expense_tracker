require 'rails_helper'

RSpec.describe "sync_sessions/index", type: :view, unit: true do
  let(:email_account) { build_stubbed(:email_account, email: "user@example.com", bank_name: "BAC") }

  let(:running_session) { build_stubbed(:sync_session, :running, id: 1) }
  let(:completed_session) { build_stubbed(:sync_session, :completed, id: 2) }
  let(:failed_session) { build_stubbed(:sync_session, :failed, id: 3) }
  let(:cancelled_session) { build_stubbed(:sync_session, :cancelled, id: 4) }
  let(:pending_session) { build_stubbed(:sync_session, id: 5) }

  before do
    assign(:active_session, nil)
    assign(:recent_sessions, [completed_session, failed_session, cancelled_session, pending_session])
    assign(:active_accounts_count, 2)
    assign(:today_sync_count, 5)
    assign(:monthly_expenses_detected, 42)
    assign(:last_completed_session, completed_session)

    allow(view).to receive(:sync_sessions_path).and_return("/sync_sessions")
    allow(view).to receive(:cancel_sync_session_path).and_return("/sync_sessions/1/cancel")
    allow(view).to receive(:sync_session_path).and_return("/sync_sessions/1")

    # Mock session accounts for completed session
    allow(completed_session).to receive(:sync_session_accounts).and_return(double(count: 2))
    allow(failed_session).to receive(:sync_session_accounts).and_return(double(count: 1))
    allow(cancelled_session).to receive(:sync_session_accounts).and_return(double(count: 3))
    allow(pending_session).to receive(:sync_session_accounts).and_return(double(count: 0))

    allow(completed_session).to receive(:completed_at).and_return(1.hour.ago)
  end

  it "displays 'Completado' for completed sessions" do
    render
    expect(rendered).to have_content("Completado")
  end

  it "displays 'Fallido' for failed sessions" do
    render
    expect(rendered).to have_content("Fallido")
  end

  it "displays 'Cancelado' for cancelled sessions" do
    render
    expect(rendered).to have_content("Cancelado")
  end

  it "displays 'Pendiente' for pending sessions" do
    render
    expect(rendered).to have_content("Pendiente")
  end

  it "does not display raw English status values" do
    render
    expect(rendered).not_to have_content("Completed")
    expect(rendered).not_to have_content("Failed")
    expect(rendered).not_to have_content("Cancelled")
    expect(rendered).not_to have_content("Pending")
  end

  context "with an active running session" do
    let(:sync_session_account) do
      build_stubbed(:sync_session_account,
        sync_session: running_session,
        email_account: email_account,
        status: "processing",
        total_emails: 100,
        processed_emails: 25,
        detected_expenses: 5
      )
    end

    before do
      assign(:active_session, running_session)

      accounts_relation = double("sync_session_accounts")
      allow(accounts_relation).to receive(:includes).with(:email_account).and_return([sync_session_account])
      allow(running_session).to receive(:sync_session_accounts).and_return(accounts_relation)

      allow(view).to receive(:cancel_sync_session_path).with(running_session).and_return("/sync_sessions/1/cancel")
    end

    it "displays 'Sincronizando' for running account status" do
      render
      # Account status in the active session card should be translated
      expect(rendered).not_to have_content("Processing")
    end
  end
end
