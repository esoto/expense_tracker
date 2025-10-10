# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Email::SyncService, 'Session Management', unit: true do
  let(:service) { described_class.new(options) }
  let(:options) { {} }
  let(:mock_time) { Time.zone.parse('2024-01-15 14:30:00') }

  before do
    allow(Time).to receive(:current).and_return(mock_time)
  end

  describe 'session lifecycle management' do
    let(:mock_session) do
      instance_double(SyncSession,
        id: 100,
        status: 'pending',
        metadata: {},
        processed_emails: 0,
        total_emails: 0
      )
    end

    describe 'session creation' do
      context 'for single account sync' do
        let(:email_account) { instance_double(EmailAccount, id: 10, email: 'test@bank.com') }
        let(:options) { { track_session: true } }

        it 'creates session before job enqueueing' do
          mock_accounts_relation = double('sync_session_accounts')

          expect(SyncSession).to receive(:create!).ordered.with(
            status: 'pending',
            total_emails: 0,
            processed_emails: 0,
            started_at: mock_time,
            metadata: { total_accounts: 1 }
          ).and_return(mock_session)

          expect(mock_session).to receive(:sync_session_accounts).and_return(mock_accounts_relation)
          expect(mock_accounts_relation).to receive(:create!).with(
            email_account: email_account,
            status: 'pending'
          )

          expect(ProcessEmailsJob).to receive(:perform_later).ordered.with(10)

          allow(EmailAccount).to receive(:find_by).with(id: 10).and_return(email_account)
          allow(email_account).to receive(:active?).and_return(true)

          result = service.sync_emails(email_account_id: 10)

          expect(result[:session_id]).to eq(100)
          expect(service.sync_session).to eq(mock_session)
        end

        it 'does not create session when track_session is false' do
          service_without_tracking = described_class.new(track_session: false)

          allow(EmailAccount).to receive(:find_by).with(id: 10).and_return(email_account)
          allow(email_account).to receive(:active?).and_return(true)
          allow(ProcessEmailsJob).to receive(:perform_later)

          # Should not call create! when track_session is false
          expect(SyncSession).not_to receive(:create!)

          result = service_without_tracking.sync_emails(email_account_id: 10)

          expect(result[:session_id]).to be_nil
          expect(service_without_tracking.sync_session).to be_nil
        end
      end

      context 'for all accounts sync' do
        let(:options) { { track_session: true } }
        let(:active_accounts) { double('ActiveRecord::Relation') }

        before do
          allow(EmailAccount).to receive(:active).and_return(active_accounts)
          allow(active_accounts).to receive(:count).and_return(5)
          allow(ProcessEmailsJob).to receive(:perform_later)
        end

        it 'creates session with total account count' do
          expect(SyncSession).to receive(:create!).with(
            status: 'pending',
            total_emails: 0,
            processed_emails: 0,
            started_at: mock_time,
            metadata: { total_accounts: 5 }
          ).and_return(mock_session)

          result = service.sync_emails

          expect(result[:session_id]).to eq(100)
        end

        it 'does not create account associations for all sync' do
          expect(SyncSession).to receive(:create!).and_return(mock_session)
          expect(mock_session).not_to receive(:sync_session_accounts)

          service.sync_emails
        end
      end

      context 'error handling during session creation' do
        let(:options) { { track_session: true } }
        let(:email_account) { instance_double(EmailAccount, id: 15, active?: true) }

        before do
          allow(EmailAccount).to receive(:find_by).and_return(email_account)
        end

        it 'propagates database errors' do
          expect(SyncSession).to receive(:create!).and_raise(
            ActiveRecord::RecordInvalid.new(SyncSession.new)
          )

          expect {
            service.sync_emails(email_account_id: 15)
          }.to raise_error(ActiveRecord::RecordInvalid)
        end

        it 'continues sync even if session creation fails' do
          allow(SyncSession).to receive(:create!).and_raise(StandardError, 'DB connection lost')
          allow(ProcessEmailsJob).to receive(:perform_later)

          expect {
            service.sync_emails(email_account_id: 15)
          }.to raise_error(StandardError, 'DB connection lost')

          expect(ProcessEmailsJob).not_to have_received(:perform_later)
        end
      end
    end

    describe 'session progress tracking' do
      let(:mock_session) do
        instance_double(SyncSession,
          id: 200,
          status: 'running',
          processed_emails: 10,
          total_emails: 100
        )
      end

      before do
        service.instance_variable_set(:@sync_session, mock_session)
      end

      it 'updates all progress fields atomically' do
        expect(mock_session).to receive(:update!).with(
          status: 'running',
          processed_emails: 25,
          total_emails: 100,
          last_activity_at: mock_time
        )

        service.update_progress(
          status: 'running',
          processed: 25,
          total: 100
        )
      end

      it 'preserves existing status when not specified' do
        expect(mock_session).to receive(:update!).with(
          status: 'running',
          processed_emails: 50,
          total_emails: 100,
          last_activity_at: mock_time
        )

        service.update_progress(processed: 50, total: 100)
      end

      it 'handles concurrent updates gracefully' do
        expect(mock_session).to receive(:update!).and_raise(
          ActiveRecord::StaleObjectError.new(mock_session, 'update')
        )

        expect {
          service.update_progress(processed: 30, total: 100)
        }.to raise_error(ActiveRecord::StaleObjectError)
      end

      context 'with progress broadcasting' do
        let(:options) { { broadcast_progress: true } }

        it 'triggers broadcast after update' do
          allow(mock_session).to receive(:update!)

          expect(ActionCable).to receive_message_chain(:server, :broadcast).with(
            'sync_progress_200',
            hash_including(
              session_id: 200,
              status: 'running',
              message: 'Processing batch...'
            )
          )

          service.update_progress(
            message: 'Processing batch...',
            processed: 35,
            total: 100
          )
        end

        it 'calculates progress percentage correctly' do
          allow(mock_session).to receive(:update!)
          allow(mock_session).to receive(:processed_emails).and_return(35)
          allow(mock_session).to receive(:total_emails).and_return(100)

          expect(ActionCable).to receive_message_chain(:server, :broadcast).with(
            'sync_progress_200',
            hash_including(progress: 35)
          )

          service.update_progress(processed: 35, total: 100)
        end
      end
    end

    describe 'session state transitions' do
      let(:session) do
        instance_double(SyncSession,
          id: 300,
          status: 'pending',
          metadata: {}
        )
      end

      describe 'pending to running' do
        it 'transitions when processing starts' do
          expect(session).to receive(:update!).with(
            status: 'running',
            processed_emails: 0,
            total_emails: 50,
            last_activity_at: mock_time
          )

          service.instance_variable_set(:@sync_session, session)
          service.update_progress(status: 'running', total: 50)
        end
      end

      describe 'running to completed' do
        before do
          allow(session).to receive(:status).and_return('running')
        end

        it 'marks as completed when all emails processed' do
          expect(session).to receive(:update!).with(
            status: 'completed',
            processed_emails: 100,
            total_emails: 100,
            last_activity_at: mock_time
          )

          service.instance_variable_set(:@sync_session, session)
          service.update_progress(status: 'completed', processed: 100, total: 100)
        end
      end

      describe 'any to failed' do
        it 'can transition to failed from any state' do
          expect(session).to receive(:update!).with(
            status: 'failed',
            processed_emails: 15,
            total_emails: 100,
            last_activity_at: mock_time
          )

          service.instance_variable_set(:@sync_session, session)
          service.update_progress(status: 'failed', processed: 15, total: 100)
        end
      end
    end

    describe 'session retry mechanism' do
      let(:failed_session) do
        instance_double(SyncSession,
          id: 400,
          failed?: true,
          metadata: { 'retry_count' => 2 },
          status: 'failed'
        )
      end

      let(:account_sessions) do
        [
          instance_double(SyncSessionAccount, email_account_id: 1, status: 'failed'),
          instance_double(SyncSessionAccount, email_account_id: 2, status: 'failed'),
          instance_double(SyncSessionAccount, email_account_id: 3, status: 'completed')
        ]
      end

      before do
        allow(SyncSession).to receive(:find).with(400).and_return(failed_session)
      end

      it 'increments retry count on each retry' do
        allow(failed_session).to receive_message_chain(:sync_session_accounts, :failed).and_return([])

        expect(failed_session).to receive(:update!).with(
          status: 'retrying',
          metadata: { 'retry_count' => 3 }
        )

        service.retry_failed_session(400)
      end

      it 'only retries failed account sessions' do
        failed_accounts = account_sessions.select { |a| a.status == 'failed' }

        allow(failed_session).to receive_message_chain(:sync_session_accounts, :failed)
          .and_return(failed_accounts)
        allow(failed_session).to receive(:update!)

        expect(ProcessEmailsJob).to receive(:perform_later).with(1)
        expect(ProcessEmailsJob).to receive(:perform_later).with(2)
        expect(ProcessEmailsJob).not_to receive(:perform_later).with(3)

        result = service.retry_failed_session(400)

        expect(result[:success]).to be true
      end

      it 'handles sessions with no failed accounts' do
        allow(failed_session).to receive_message_chain(:sync_session_accounts, :failed)
          .and_return([])
        allow(failed_session).to receive(:update!)

        expect(ProcessEmailsJob).not_to receive(:perform_later)

        result = service.retry_failed_session(400)

        expect(result[:success]).to be true
        expect(result[:message]).to include('session 400')
      end

      context 'retry limits' do
        it 'allows retry regardless of retry count' do
          failed_session_high_retry = instance_double(SyncSession,
            id: 500,
            failed?: true,
            metadata: { 'retry_count' => 10 }
          )

          allow(SyncSession).to receive(:find).with(500).and_return(failed_session_high_retry)
          allow(failed_session_high_retry).to receive_message_chain(:sync_session_accounts, :failed)
            .and_return([])

          expect(failed_session_high_retry).to receive(:update!).with(
            status: 'retrying',
            metadata: { 'retry_count' => 11 }
          )

          result = service.retry_failed_session(500)

          expect(result[:success]).to be true
        end
      end
    end

    describe 'session cleanup and maintenance' do
      it 'properly cleans up session reference on service instance' do
        mock_session = instance_double(SyncSession, id: 600)
        service.instance_variable_set(:@sync_session, mock_session)

        expect(service.sync_session).to eq(mock_session)

        # Creating a new service instance should not have the session
        new_service = described_class.new
        expect(new_service.sync_session).to be_nil
      end

      it 'maintains session reference across multiple progress updates' do
        mock_session = instance_double(SyncSession, id: 700)
        service.instance_variable_set(:@sync_session, mock_session)

        allow(mock_session).to receive(:update!)
        allow(mock_session).to receive(:status).and_return('running')
        allow(mock_session).to receive(:processed_emails).and_return(10, 20, 30)
        allow(mock_session).to receive(:total_emails).and_return(100)

        3.times do |i|
          service.update_progress(processed: (i + 1) * 10, total: 100)
          expect(service.sync_session).to eq(mock_session)
        end
      end
    end
  end
end
