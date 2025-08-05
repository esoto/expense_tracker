require 'rails_helper'

RSpec.describe "SyncSessions", type: :system do
  let(:email_account) { create(:email_account) }
  let!(:sync_session) { create(:sync_session, :running) }
  let!(:sync_account) { create(:sync_session_account, sync_session: sync_session, email_account: email_account, status: 'processing', total_emails: 100, processed_emails: 25) }

  describe "GET /sync_sessions" do
    it "displays list of sync sessions" do
      visit sync_sessions_path

      expect(page).to have_content("Centro de Sincronización")
      expect(page).to have_content("Sincronizando")
      expect(page).to have_content("25%") # Progress
    end

    it "has working navigation links" do
      visit sync_sessions_path

      # Find the first View link and click it
      first(:link, "Ver Detalles").click

      # Just check we're on a sync session show page
      expect(page).to have_content("Detalles de Sincronización")
    end

    context "with multiple sessions" do
      let!(:completed_session) { create(:sync_session, :completed, total_emails: 200, processed_emails: 200, detected_expenses: 15) }
      let!(:failed_session) { create(:sync_session, :failed) }

      it "displays all sessions with correct statuses" do
        visit sync_sessions_path

        expect(page).to have_content("Sincronizando")
        expect(page).to have_content("Completed")
        expect(page).to have_content("Failed")
        expect(page).to have_content("15") # Detected expenses count
      end
    end
  end

  describe "GET /sync_sessions/:id" do
    it "displays sync session details" do
      visit sync_session_path(sync_session)

      expect(page).to have_content("Detalles de Sincronización")
      expect(page).to have_content("Sincronizando")
      expect(page).to have_content("25%")
      expect(page).to have_content(email_account.email)
    end

    it "displays account statuses" do
      visit sync_session_path(sync_session)

      within ".lg\\:col-span-2" do
        expect(page).to have_content(email_account.email)
        expect(page).to have_content("Processing")
        expect(page).to have_content("25 / 100")
      end
    end

    it "has working back link" do
      visit sync_session_path(sync_session)

      # Find the back link more precisely
      find("a[href='#{sync_sessions_path}']", match: :first).click

      # Just check we're back on the sync sessions index
      expect(page).to have_content("Centro de Sincronización")
      # Removed as this text no longer exists in the UI
    end

    context "with completed session" do
      let(:completed_session) { create(:sync_session, :completed) }
      let!(:completed_account) { create(:sync_session_account, :completed, sync_session: completed_session, email_account: email_account) }

      it "displays completion information" do
        visit sync_session_path(completed_session)

        expect(page).to have_content("Completed")
        # The progress is shown in the summary section
        within ".lg\\:col-span-1" do
          expect(page).to have_content("100")
        end
      end
    end

    context "with failed accounts" do
      let!(:failed_account) { create(:sync_session_account, :failed, sync_session: sync_session, email_account: create(:email_account)) }

      it "displays error information" do
        visit sync_session_path(sync_session)

        expect(page).to have_content("Failed")
        find("summary", text: "Ver error").click
        expect(page).to have_content("IMAP connection failed")
      end
    end
  end

  describe "cancel sync session" do
    it "cancels a running sync session" do
      visit sync_session_path(sync_session)

      expect(page).to have_button("Cancelar Sincronización")

      click_button "Cancelar Sincronización"

      expect(page).to have_content("Sincronización cancelada exitosamente")
      expect(sync_session.reload).to be_cancelled
    end
  end

  describe "status badges" do
    it "displays correct status colors" do
      # Create sessions with completed_at for completed ones
      create(:sync_session, status: 'pending')
      create(:sync_session, status: 'running')
      create(:sync_session, status: 'completed', completed_at: 1.hour.ago)
      create(:sync_session, status: 'failed')
      create(:sync_session, status: 'cancelled')

      visit sync_sessions_path

      expect(page).to have_css(".bg-slate-100")
      expect(page).to have_css(".bg-teal-100")
      expect(page).to have_css(".bg-emerald-100")
      expect(page).to have_css(".bg-rose-100")
    end
  end

  describe "progress display" do
    it "shows progress for active sessions" do
      visit sync_sessions_path

      expect(page).to have_content("25 / 100")
    end

    it "shows progress for running sessions" do
      # Simulate a session that has been running for a while
      sync_session.update!(started_at: 1.minute.ago)
      sync_account.update!(processed_emails: 50, total_emails: 100)

      visit sync_session_path(sync_session)

      # The session itself still shows 25% from the initial state
      expect(page).to have_content("25%")
      # But the account shows updated progress
      expect(page).to have_content("50 / 100")
    end
  end
end
