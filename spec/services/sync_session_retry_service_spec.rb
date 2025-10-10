require 'rails_helper'

RSpec.describe Services::SyncSessionRetryService, integration: true do
  let(:email_account) { create(:email_account, active: true) }
  let(:original_session) { create(:sync_session, :failed) }
  let(:params) { {} }
  let(:service) { described_class.new(original_session, params) }

  before do
    original_session.email_accounts << email_account
    allow(ProcessEmailsJob).to receive(:perform_later)
  end

  describe '#call', integration: true do
    context 'with valid retry conditions' do
      before do
        # Ensure rate limiting is not active for these tests
        allow_any_instance_of(SyncSessionValidator).to receive(:can_create_sync?).and_return(true)
      end

      it 'creates a new sync session' do
        expect { service.call }.to change(SyncSession, :count).by(1)
      end

      it 'copies email accounts from original session' do
        result = service.call
        expect(result.sync_session.email_accounts).to eq([ email_account ])
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

      context 'with custom since date' do
        let(:since_date) { Date.parse('2025-01-01') }
        let(:params) { { since: since_date } }

        it 'uses the provided since date' do
          result = service.call
          expect(ProcessEmailsJob).to have_received(:perform_later).with(
            nil,
            since: since_date,
            sync_session_id: result.sync_session.id
          )
        end
      end

      context 'when original was cancelled' do
        let(:original_session) { create(:sync_session, status: 'cancelled') }

        it 'allows retry' do
          result = service.call
          expect(result).to be_success
        end
      end
    end

    context 'with invalid retry conditions' do
      context 'when session is not failed or cancelled' do
        let(:original_session) { create(:sync_session, :running) }

        it 'returns a failure result' do
          result = service.call
          expect(result).to be_failure
          expect(result.error).to eq(:invalid_status)
        end

        it 'does not create a new session' do
          expect { service.call }.not_to change(SyncSession, :count)
        end
      end

      context 'when rate limit is exceeded' do
        before do
          allow_any_instance_of(SyncSessionValidator).to receive(:can_create_sync?).and_return(false)
        end

        it 'returns a failure result' do
          result = service.call
          expect(result).to be_failure
          expect(result.error).to eq(:rate_limit_exceeded)
        end
      end
    end

    context 'with unexpected errors' do
      before do
        # Allow rate limiting to pass but cause error during session creation
        allow_any_instance_of(SyncSessionValidator).to receive(:can_create_sync?).and_return(true)
        allow(SyncSession).to receive(:create!).and_raise(StandardError, "Unexpected error")
      end

      it 'returns a failure result' do
        result = service.call
        expect(result).to be_failure
        expect(result.error).to eq(:unexpected_error)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Error retrying sync session/)
        service.call
      end
    end
  end
end
