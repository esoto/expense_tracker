require 'rails_helper'

RSpec.describe SyncSessionCreator, integration: true do
  let(:email_account) { create(:email_account, active: true) }
  let(:params) { {} }
  let(:service) { described_class.new(params) }

  describe '#call', integration: true do
    before do
      allow(ProcessEmailsJob).to receive(:perform_later)
    end

    context 'with valid parameters' do
      context 'when creating sync for all accounts' do
        let!(:account1) { create(:email_account, active: true) }
        let!(:account2) { create(:email_account, active: true) }

        it 'creates a sync session with all active accounts' do
          expect { service.call }.to change(SyncSession, :count).by(1)
        end

        it 'associates all active accounts' do
          result = service.call
          expect(result.sync_session.email_accounts).to match_array([ account1, account2 ])
        end

        it 'enqueues ProcessEmailsJob' do
          result = service.call
          expect(ProcessEmailsJob).to have_received(:perform_later).with(
            nil,
            since: be_within(1.second).of(1.week.ago),
            sync_session_id: result.sync_session.id
          )
        end

        it 'returns a successful result' do
          result = service.call
          expect(result).to be_success
          expect(result.sync_session).to be_a(SyncSession)
        end
      end

      context 'when creating sync for specific account' do
        let(:params) { { email_account_id: email_account.id } }

        it 'creates a sync session with the specified account' do
          result = service.call
          expect(result.sync_session.email_accounts).to eq([ email_account ])
        end

        it 'enqueues ProcessEmailsJob with account id' do
          result = service.call
          expect(ProcessEmailsJob).to have_received(:perform_later).with(
            email_account.id,
            since: be_within(1.second).of(1.week.ago),
            sync_session_id: result.sync_session.id
          )
        end
      end

      context 'with custom since date' do
        let(:since_date) { Date.parse('2025-01-01') }
        let(:params) { { since: since_date } }
        let!(:account) { create(:email_account, active: true) }

        it 'uses the provided since date' do
          result = service.call
          expect(result).to be_success
          expect(ProcessEmailsJob).to have_received(:perform_later).with(
            nil,
            since: since_date,
            sync_session_id: result.sync_session.id
          )
        end
      end
    end

    context 'with validation errors' do
      context 'when sync limit is exceeded' do
        before do
          create(:sync_session, status: 'running')
        end

        it 'returns a failure result' do
          result = service.call
          expect(result).to be_failure
          expect(result.error).to eq(:sync_limit_exceeded)
        end

        it 'does not create a sync session' do
          expect { service.call }.not_to change(SyncSession, :count)
        end
      end

      context 'when rate limit is exceeded' do
        before do
          3.times { create(:sync_session, status: 'completed', created_at: 2.minutes.ago) }
        end

        it 'returns a failure result' do
          result = service.call
          expect(result).to be_failure
          expect(result.error).to eq(:rate_limit_exceeded)
        end
      end

      context 'when email account not found' do
        let(:params) { { email_account_id: 99999 } }

        it 'returns a failure result' do
          result = service.call
          expect(result).to be_failure
          expect(result.error).to eq(:account_not_found)
        end
      end

      context 'when no active accounts exist' do
        before do
          EmailAccount.update_all(active: false)
        end

        it 'returns a failure result' do
          result = service.call
          expect(result).to be_failure
          expect(result.error).to eq(:validation_error)
        end
      end
    end

    context 'with unexpected errors' do
      before do
        allow(SyncSession).to receive(:create!).and_raise(StandardError, "Unexpected error")
      end

      it 'returns a failure result' do
        result = service.call
        expect(result).to be_failure
        expect(result.error).to eq(:unexpected_error)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Unexpected error creating sync session/)
        service.call
      end
    end
  end
end
