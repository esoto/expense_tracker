require 'rails_helper'

RSpec.describe "SyncSessions", type: :request do
  let!(:email_account1) { create(:email_account, :bac, active: true) }
  let!(:email_account2) { create(:email_account, :gmail, active: true) }
  let!(:inactive_account) { create(:email_account, active: false) }

  describe 'GET /sync_sessions' do
    let!(:active_session) { create(:sync_session, :running) }
    let!(:completed_session) { create(:sync_session, :completed) }
    let!(:old_session) { create(:sync_session, created_at: 2.days.ago) }

    before do
      active_session.email_accounts << email_account1
      completed_session.email_accounts << [ email_account1, email_account2 ]
    end

    it 'returns http success' do
      get sync_sessions_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /sync_sessions/:id' do
    let(:sync_session) { create(:sync_session) }
    let!(:session_account1) { create(:sync_session_account, sync_session: sync_session, email_account: email_account1) }
    let!(:session_account2) { create(:sync_session_account, sync_session: sync_session, email_account: email_account2) }

    context 'with valid id' do
      it 'returns http success' do
        get sync_session_path(sync_session)
        expect(response).to have_http_status(:success)
      end
    end

    context 'with invalid id' do
      it 'redirects with alert for invalid id' do
        get sync_session_path(id: 99999)
        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to eq("Sincronización no encontrada")
      end
    end
  end

  describe 'POST /sync_sessions' do
    before do
      allow(ProcessEmailsJob).to receive(:perform_later)
    end

    context 'with specific email_account_id' do
      it 'creates a new sync session' do
        expect {
          post sync_sessions_path, params: { email_account_id: email_account1.id }
        }.to change(SyncSession, :count).by(1)
      end

      it 'adds only the specified email account to the session' do
        post sync_sessions_path, params: { email_account_id: email_account1.id }
        session = SyncSession.last
        expect(session.email_accounts).to eq([ email_account1 ])
      end

      it 'enqueues ProcessEmailsJob with correct parameters' do
        post sync_sessions_path, params: { email_account_id: email_account1.id }
        session = SyncSession.last

        expect(ProcessEmailsJob).to have_received(:perform_later).with(
          email_account1.id.to_s,
          since: be_within(1.second).of(1.week.ago),
          sync_session_id: session.id
        )
      end

      it 'redirects to sync_sessions_path with success notice' do
        post sync_sessions_path, params: { email_account_id: email_account1.id }
        expect(response).to redirect_to(sync_sessions_path)
        follow_redirect!
        expect(response.body).to include("Sincronización iniciada exitosamente")
      end
    end

    context 'without email_account_id (all accounts)' do
      it 'creates a new sync session' do
        expect {
          post sync_sessions_path
        }.to change(SyncSession, :count).by(1)
      end

      it 'adds all active email accounts to the session' do
        post sync_sessions_path
        session = SyncSession.last
        expect(session.email_accounts).to match_array([ email_account1, email_account2 ])
      end

      it 'does not add inactive accounts' do
        post sync_sessions_path
        session = SyncSession.last
        expect(session.email_accounts).not_to include(inactive_account)
      end

      it 'enqueues ProcessEmailsJob with nil account_id' do
        post sync_sessions_path
        session = SyncSession.last

        expect(ProcessEmailsJob).to have_received(:perform_later).with(
          nil,
          since: be_within(1.second).of(1.week.ago),
          sync_session_id: session.id
        )
      end
    end

    context 'with invalid email_account_id' do
      it 'redirects with error message' do
        post sync_sessions_path, params: { email_account_id: 99999 }
        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to include("Cuenta de email no encontrada")
      end
    end

    context 'with sync limit validation' do
      before do
        # Create an active sync session
        create(:sync_session, status: 'running')
      end

      it 'prevents creating another sync session' do
        expect {
          post sync_sessions_path
        }.not_to change(SyncSession, :count)

        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to include("Ya hay una sincronización activa")
      end
    end

    context 'with rate limit validation' do
      before do
        # Create 3 completed sync sessions in the last 5 minutes
        3.times { create(:sync_session, status: 'completed', created_at: 2.minutes.ago) }
      end

      it 'prevents creating another sync session' do
        expect {
          post sync_sessions_path
        }.not_to change(SyncSession, :count)

        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to include("Has alcanzado el límite de sincronizaciones")
      end
    end

    context 'with custom since parameter' do
      it 'passes the since parameter to the job' do
        post sync_sessions_path, params: { since: '2025-01-01' }
        session = SyncSession.last

        expect(ProcessEmailsJob).to have_received(:perform_later).with(
          nil,
          since: Date.parse('2025-01-01'),
          sync_session_id: session.id
        )
      end
    end
  end

  describe 'POST /sync_sessions/:id/cancel' do
    context 'with active session' do
      let(:sync_session) { create(:sync_session, :running) }

      it 'cancels the session' do
        post cancel_sync_session_path(sync_session)
        expect(sync_session.reload).to be_cancelled
      end

      it 'redirects with success notice' do
        post cancel_sync_session_path(sync_session)
        expect(response).to redirect_to(sync_sessions_path)
        follow_redirect!
        expect(response.body).to include("Sincronización cancelada")
      end
    end

    context 'with pending session' do
      let(:sync_session) { create(:sync_session, status: 'pending') }

      it 'cancels the session' do
        post cancel_sync_session_path(sync_session)
        expect(sync_session.reload).to be_cancelled
      end
    end

    context 'with completed session' do
      let(:sync_session) { create(:sync_session, :completed) }

      it 'does not cancel the session' do
        post cancel_sync_session_path(sync_session)
        expect(sync_session.reload).to be_completed
      end

      it 'redirects with alert' do
        post cancel_sync_session_path(sync_session)
        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to eq("Esta sincronización no está activa")
      end
    end
  end

  describe 'POST /sync_sessions/:id/retry' do
    before do
      allow(ProcessEmailsJob).to receive(:perform_later)
    end

    context 'with failed session' do
      let(:sync_session) { create(:sync_session, :failed) }

      before do
        sync_session.email_accounts << [ email_account1, email_account2 ]
      end

      it 'creates a new sync session' do
        expect {
          post retry_sync_session_path(sync_session)
        }.to change(SyncSession, :count).by(1)
      end

      it 'copies email accounts to new session' do
        post retry_sync_session_path(sync_session)
        new_session = SyncSession.last
        expect(new_session.email_accounts).to match_array([ email_account1, email_account2 ])
      end

      it 'enqueues ProcessEmailsJob for new session' do
        post retry_sync_session_path(sync_session)
        new_session = SyncSession.last

        expect(ProcessEmailsJob).to have_received(:perform_later).with(
          nil,
          since: be_within(1.second).of(1.week.ago),
          sync_session_id: new_session.id
        )
      end

      it 'redirects with success notice' do
        post retry_sync_session_path(sync_session)
        expect(response).to redirect_to(sync_sessions_path)
        follow_redirect!
        expect(response.body).to include("Sincronización reiniciada")
      end
    end

    context 'with cancelled session' do
      let(:sync_session) { create(:sync_session, :cancelled) }

      before do
        sync_session.email_accounts << email_account1
      end

      it 'creates a new sync session' do
        expect {
          post retry_sync_session_path(sync_session)
        }.to change(SyncSession, :count).by(1)
      end
    end

    context 'with running session' do
      let!(:sync_session) { create(:sync_session, :running) }

      it 'does not create a new session' do
        initial_count = SyncSession.count
        post retry_sync_session_path(sync_session)
        expect(SyncSession.count).to eq(initial_count)
      end

      it 'redirects with alert' do
        post retry_sync_session_path(sync_session)
        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to eq("Solo se pueden reintentar sincronizaciones fallidas o canceladas")
      end
    end

    context 'with rate limit exceeded' do
      let(:sync_session) { create(:sync_session, :failed) }

      before do
        sync_session.email_accounts << email_account1
        # Create 3 sync sessions to exceed rate limit
        3.times { create(:sync_session, created_at: 2.minutes.ago) }
      end

      it 'prevents retry due to rate limit' do
        expect {
          post retry_sync_session_path(sync_session)
        }.not_to change(SyncSession, :count)

        expect(response).to redirect_to(sync_sessions_path)
        expect(flash[:alert]).to include("Has alcanzado el límite de sincronizaciones")
      end
    end

    context 'JSON format' do
      let(:sync_session) { create(:sync_session, :failed) }

      before do
        sync_session.email_accounts << email_account1
      end

      it 'returns created status on success' do
        post retry_sync_session_path(sync_session), as: :json

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json).to have_key('id')
        expect(json['status']).to eq('pending')
      end
    end
  end

  describe 'GET /sync_sessions/status' do
    let(:sync_session) { create(:sync_session, :running,
                                total_emails: 100,
                                processed_emails: 50,
                                detected_expenses: 15,
                                started_at: 1.minute.ago) }
    let!(:session_account) { create(:sync_session_account,
                                   sync_session: sync_session,
                                   email_account: email_account1,
                                   status: 'processing',
                                   total_emails: 100,
                                   processed_emails: 50,
                                   detected_expenses: 15) }

    context 'with valid sync_session_id' do
      it 'returns success response' do
        get status_sync_sessions_path, params: { sync_session_id: sync_session.id }
        expect(response).to have_http_status(:success)
      end

      it 'returns json with session status' do
        get status_sync_sessions_path, params: { sync_session_id: sync_session.id }
        json = JSON.parse(response.body)

        expect(json['status']).to eq('running')
        expect(json['progress_percentage']).to eq(50)
        expect(json['processed_emails']).to eq(50)
        expect(json['total_emails']).to eq(100)
        expect(json['detected_expenses']).to eq(15)
        expect(json['time_remaining']).to be_present
      end

      it 'includes account details' do
        get status_sync_sessions_path, params: { sync_session_id: sync_session.id }
        json = JSON.parse(response.body)

        expect(json['accounts']).to be_an(Array)
        expect(json['accounts'].length).to eq(1)

        account_data = json['accounts'].first
        expect(account_data['id']).to eq(session_account.id)
        expect(account_data['email']).to eq(email_account1.email)
        expect(account_data['bank']).to eq(email_account1.bank_name)
        expect(account_data['status']).to eq('processing')
        expect(account_data['progress']).to eq(50)
        expect(account_data['processed']).to eq(50)
        expect(account_data['total']).to eq(100)
        expect(account_data['detected']).to eq(15)
      end
    end

    context 'with invalid sync_session_id' do
      it 'returns not found status' do
        get status_sync_sessions_path, params: { sync_session_id: 99999 }
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error json' do
        get status_sync_sessions_path, params: { sync_session_id: 99999 }
        json = JSON.parse(response.body)
        expect(json['error']).to eq("Session not found")
      end
    end
  end
end
