# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Email::SyncService, unit: true do
  let(:service) { described_class.new(options) }
  let(:options) { {} }
  let(:mock_time) { Time.zone.parse('2024-01-15 10:00:00') }

  before do
    allow(Time).to receive(:current).and_return(mock_time)
  end

  describe '#initialize' do
    it 'initializes with default values' do
      expect(service.metrics).to eq({})
      expect(service.errors).to eq([])
      expect(service.sync_session).to be_nil
    end

    it 'accepts options hash' do
      service = described_class.new(track_session: true, broadcast_progress: true)
      expect(service.instance_variable_get(:@options)).to include(
        track_session: true,
        broadcast_progress: true
      )
    end
  end

  describe '#sync_emails' do
    let(:active_account) { instance_double(EmailAccount, id: 1, email: 'test@example.com', active?: true) }
    let(:inactive_account) { instance_double(EmailAccount, id: 2, email: 'inactive@example.com', active?: false) }

    context 'with specific email account' do
      before do
        allow(EmailAccount).to receive(:find_by).with(id: 1).and_return(active_account)
        allow(ProcessEmailsJob).to receive(:perform_later)
      end

      it 'syncs specific active account successfully' do
        result = service.sync_emails(email_account_id: 1)

        expect(result[:success]).to be true
        expect(result[:message]).to include('test@example.com')
        expect(result[:email_account]).to eq(active_account)
        expect(ProcessEmailsJob).to have_received(:perform_later).with(1)
      end

      it 'includes session_id when track_session is enabled' do
        service = described_class.new(track_session: true)
        mock_session = instance_double(SyncSession, id: 99)
        
        allow(SyncSession).to receive(:create!).and_return(mock_session)
        allow(mock_session).to receive_message_chain(:sync_session_accounts, :create!)
        allow(EmailAccount).to receive(:find_by).with(id: 1).and_return(active_account)
        allow(ProcessEmailsJob).to receive(:perform_later)

        result = service.sync_emails(email_account_id: 1)

        expect(result[:session_id]).to eq(99)
      end

      it 'raises SyncError for non-existent account' do
        allow(EmailAccount).to receive(:find_by).with(id: 999).and_return(nil)

        expect {
          service.sync_emails(email_account_id: 999)
        }.to raise_error(Email::SyncService::SyncError, 'Cuenta de correo no encontrada.')
      end

      it 'raises SyncError for inactive account' do
        allow(EmailAccount).to receive(:find_by).with(id: 2).and_return(inactive_account)

        expect {
          service.sync_emails(email_account_id: 2)
        }.to raise_error(Email::SyncService::SyncError, 'La cuenta de correo está inactiva.')
      end
    end

    context 'without email account (sync all)' do
      let(:active_accounts) { double('ActiveRecord::Relation') }

      before do
        allow(EmailAccount).to receive(:active).and_return(active_accounts)
        allow(ProcessEmailsJob).to receive(:perform_later)
      end

      it 'syncs all active accounts successfully' do
        allow(active_accounts).to receive(:count).and_return(3)

        result = service.sync_emails

        expect(result[:success]).to be true
        expect(result[:message]).to include('3 cuentas de correo')
        expect(result[:account_count]).to eq(3)
        expect(ProcessEmailsJob).to have_received(:perform_later).with(no_args)
      end

      it 'handles singular correctly for single account' do
        allow(active_accounts).to receive(:count).and_return(1)

        result = service.sync_emails

        expect(result[:message]).to include('1 cuenta de correo')
        expect(result[:message]).not_to include('cuentas')
      end

      it 'raises SyncError when no active accounts exist' do
        allow(active_accounts).to receive(:count).and_return(0)

        expect {
          service.sync_emails
        }.to raise_error(Email::SyncService::SyncError, 'No hay cuentas de correo activas configuradas.')
      end

      context 'with conflict detection enabled' do
        let(:options) { { detect_conflicts: true } }
        let(:conflicts) { [{ type: 'duplicate', expenses: [1, 2], confidence: 0.8 }] }

        before do
          allow(active_accounts).to receive(:count).and_return(2)
        end

        it 'detects conflicts after sync' do
          expect(service).to receive(:detect_conflicts).and_return(conflicts)
          expect(service).not_to receive(:resolve_conflicts)

          result = service.sync_emails

          expect(result[:success]).to be true
        end

        context 'with auto_resolve enabled' do
          let(:options) { { detect_conflicts: true, auto_resolve: true } }

          it 'resolves conflicts automatically when detected' do
            expect(service).to receive(:detect_conflicts).and_return(conflicts)
            expect(service).to receive(:resolve_conflicts).with(conflicts)

            result = service.sync_emails

            expect(result[:success]).to be true
          end

          it 'does not resolve when no conflicts detected' do
            expect(service).to receive(:detect_conflicts).and_return([])
            expect(service).not_to receive(:resolve_conflicts)

            result = service.sync_emails

            expect(result[:success]).to be true
          end
        end
      end
    end
  end

  describe '#create_session' do
    let(:mock_session) { instance_double(SyncSession, id: 10) }
    let(:email_account) { instance_double(EmailAccount, id: 5) }

    context 'without email account' do
      before do
        allow(EmailAccount).to receive_message_chain(:active, :count).and_return(3)
      end

      it 'creates session for all accounts' do
        expect(SyncSession).to receive(:create!).with(
          status: 'pending',
          total_emails: 0,
          processed_emails: 0,
          started_at: mock_time,
          metadata: { total_accounts: 3 }
        ).and_return(mock_session)

        result = service.create_session

        expect(result).to eq(mock_session)
        expect(service.sync_session).to eq(mock_session)
      end
    end

    context 'with specific email account' do
      it 'creates session with account association' do
        mock_accounts = double('sync_session_accounts')
        
        expect(SyncSession).to receive(:create!).with(
          status: 'pending',
          total_emails: 0,
          processed_emails: 0,
          started_at: mock_time,
          metadata: { total_accounts: 1 }
        ).and_return(mock_session)

        expect(mock_session).to receive(:sync_session_accounts).and_return(mock_accounts)
        expect(mock_accounts).to receive(:create!).with(
          email_account: email_account,
          status: 'pending'
        )

        result = service.create_session(email_account)

        expect(result).to eq(mock_session)
      end
    end

    it 'handles database errors gracefully' do
      allow(EmailAccount).to receive_message_chain(:active, :count).and_return(2)
      allow(SyncSession).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        service.create_session
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#update_progress' do
    context 'without sync_session' do
      it 'returns early without updating' do
        expect(service.sync_session).to be_nil
        expect {
          service.update_progress(status: 'running', processed: 10, total: 100)
        }.not_to raise_error
      end
    end

    context 'with sync_session' do
      let(:mock_session) do
        instance_double(SyncSession,
          id: 20,
          status: 'pending',
          processed_emails: 0,
          total_emails: 0
        )
      end

      before do
        service.instance_variable_set(:@sync_session, mock_session)
      end

      it 'updates session with provided values' do
        expect(mock_session).to receive(:update!).with(
          status: 'running',
          processed_emails: 25,
          total_emails: 100,
          last_activity_at: mock_time
        )

        service.update_progress(status: 'running', processed: 25, total: 100)
      end

      it 'keeps existing status when not provided' do
        expect(mock_session).to receive(:update!).with(
          status: 'pending',
          processed_emails: 10,
          total_emails: 50,
          last_activity_at: mock_time
        )

        service.update_progress(processed: 10, total: 50)
      end

      context 'with broadcast_progress enabled' do
        let(:options) { { broadcast_progress: true } }

        it 'broadcasts progress update' do
          allow(mock_session).to receive(:update!)
          expect(service).to receive(:broadcast_progress).with('Processing emails...')

          service.update_progress(message: 'Processing emails...', processed: 5, total: 20)
        end
      end

      context 'without broadcast_progress' do
        it 'does not broadcast progress' do
          allow(mock_session).to receive(:update!)
          expect(service).not_to receive(:broadcast_progress)

          service.update_progress(message: 'Processing...', processed: 5, total: 20)
        end
      end
    end
  end

  describe '#retry_failed_session' do
    let(:failed_session) do
      instance_double(SyncSession,
        id: 30,
        failed?: true,
        metadata: { 'retry_count' => 1 }
      )
    end

    let(:failed_account_session) do
      instance_double(SyncSessionAccount,
        email_account_id: 5,
        status: 'failed'
      )
    end

    context 'with valid failed session' do
      before do
        allow(SyncSession).to receive(:find).with(30).and_return(failed_session)
        allow(failed_session).to receive_message_chain(:sync_session_accounts, :failed)
          .and_return([failed_account_session])
      end

      it 'updates session status and increments retry count' do
        expect(failed_session).to receive(:update!).with(
          status: 'retrying',
          metadata: { 'retry_count' => 2 }
        )
        expect(ProcessEmailsJob).to receive(:perform_later).with(5)

        result = service.retry_failed_session(30)

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Retry initiated for session 30')
      end

      it 're-runs sync for all failed accounts' do
        failed_account2 = instance_double(SyncSessionAccount, email_account_id: 8)
        
        allow(failed_session).to receive_message_chain(:sync_session_accounts, :failed)
          .and_return([failed_account_session, failed_account2])
        allow(failed_session).to receive(:update!)

        expect(ProcessEmailsJob).to receive(:perform_later).with(5)
        expect(ProcessEmailsJob).to receive(:perform_later).with(8)

        service.retry_failed_session(30)
      end
    end

    context 'with non-existent session' do
      before do
        allow(SyncSession).to receive(:find).with(999).and_return(nil)
      end

      it 'returns error for non-existent session' do
        result = service.retry_failed_session(999)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session not found')
      end
    end

    context 'with non-failed session' do
      let(:completed_session) do
        instance_double(SyncSession, id: 40, failed?: false)
      end

      before do
        allow(SyncSession).to receive(:find).with(40).and_return(completed_session)
      end

      it 'returns error for non-failed session' do
        result = service.retry_failed_session(40)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Session not failed')
      end
    end
  end

  describe '#get_metrics' do
    let(:time_window) { 1.hour } # Default time window in service
    let(:time_range) { (mock_time - time_window)..mock_time }

    before do
      # Mock SyncSession queries
      sessions_scope = double('sessions_scope')
      allow(SyncSession).to receive(:where).with(created_at: time_range).and_return(sessions_scope)
      allow(sessions_scope).to receive(:count).and_return(10)

      completed_scope = double('completed_scope')
      allow(SyncSession).to receive(:completed).and_return(completed_scope)
      allow(completed_scope).to receive(:where).with(created_at: time_range).and_return(completed_scope)
      allow(completed_scope).to receive(:count).and_return(7)

      failed_scope = double('failed_scope')
      allow(SyncSession).to receive(:failed).and_return(failed_scope)
      allow(failed_scope).to receive(:where).with(created_at: time_range).and_return(failed_scope)
      allow(failed_scope).to receive(:count).and_return(2)

      # Mock private method returns
      allow(service).to receive(:calculate_average_duration).with(time_window).and_return(45.5)
      allow(service).to receive(:calculate_emails_processed).with(time_window).and_return(250)
      allow(service).to receive(:calculate_conflicts).with(time_window).and_return(3)
    end

    it 'returns comprehensive metrics for default time window' do
      metrics = service.get_metrics

      expect(metrics).to eq({
        total_syncs: 10,
        successful_syncs: 7,
        failed_syncs: 2,
        average_duration: 45.5,
        emails_processed: 250,
        conflicts_detected: 3
      })
    end

    it 'accepts custom time window' do
      custom_window = 6.hours
      custom_range = (mock_time - custom_window)..mock_time

      sessions_scope = double('sessions_scope')
      allow(SyncSession).to receive(:where).with(created_at: custom_range).and_return(sessions_scope)
      allow(sessions_scope).to receive(:count).and_return(25)

      completed_scope = double('completed_scope')
      allow(SyncSession).to receive(:completed).and_return(completed_scope)
      allow(completed_scope).to receive(:where).with(created_at: custom_range).and_return(completed_scope)
      allow(completed_scope).to receive(:count).and_return(20)

      failed_scope = double('failed_scope')
      allow(SyncSession).to receive(:failed).and_return(failed_scope)
      allow(failed_scope).to receive(:where).with(created_at: custom_range).and_return(failed_scope)
      allow(failed_scope).to receive(:count).and_return(3)

      allow(service).to receive(:calculate_average_duration).with(custom_window).and_return(60.0)
      allow(service).to receive(:calculate_emails_processed).with(custom_window).and_return(500)
      allow(service).to receive(:calculate_conflicts).with(custom_window).and_return(5)

      metrics = service.get_metrics(time_window: custom_window)

      expect(metrics[:total_syncs]).to eq(25)
    end
  end

  describe 'SyncError' do
    it 'is a StandardError subclass' do
      error = Email::SyncService::SyncError.new
      expect(error).to be_a(StandardError)
    end

    it 'accepts custom error messages' do
      error = Email::SyncService::SyncError.new('Custom sync error')
      expect(error.message).to eq('Custom sync error')
    end
  end
end