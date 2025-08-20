require 'rails_helper'

RSpec.describe SyncSessionAccount, type: :model, integration: true do
  include ActiveSupport::Testing::TimeHelpers

  describe 'associations', integration: true do
    it { should belong_to(:sync_session) }
    it { should belong_to(:email_account) }
  end

  describe 'validations', integration: true do
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[pending waiting processing completed failed]) }
  end

  describe 'scopes', integration: true do
    before do
      SyncSessionAccount.destroy_all
    end

    let!(:pending_account) { create(:sync_session_account, status: 'pending') }
    let!(:waiting_account) { create(:sync_session_account, status: 'waiting') }
    let!(:processing_account) { create(:sync_session_account, status: 'processing') }
    let!(:completed_account) { create(:sync_session_account, status: 'completed') }
    let!(:failed_account) { create(:sync_session_account, status: 'failed') }

    describe '.active', integration: true do
      it 'returns only processing accounts' do
        expect(SyncSessionAccount.active.to_a).to eq([ processing_account ])
      end
    end

    describe '.completed', integration: true do
      it 'returns only completed accounts' do
        expect(SyncSessionAccount.completed.to_a).to eq([ completed_account ])
      end
    end

    describe '.failed', integration: true do
      it 'returns only failed accounts' do
        expect(SyncSessionAccount.failed.to_a).to eq([ failed_account ])
      end
    end
  end

  describe '#progress_percentage', integration: true do
    subject(:session_account) { build(:sync_session_account, total_emails: total, processed_emails: processed) }

    context 'when total_emails is zero' do
      let(:total) { 0 }
      let(:processed) { 0 }

      it 'returns 0' do
        expect(session_account.progress_percentage).to eq(0)
      end
    end

    context 'when some emails are processed' do
      let(:total) { 100 }
      let(:processed) { 25 }

      it 'returns the correct percentage' do
        expect(session_account.progress_percentage).to eq(25)
      end
    end

    context 'when all emails are processed' do
      let(:total) { 50 }
      let(:processed) { 50 }

      it 'returns 100' do
        expect(session_account.progress_percentage).to eq(100)
      end
    end

    context 'with fractional percentages' do
      let(:total) { 3 }
      let(:processed) { 2 }

      it 'rounds to nearest integer' do
        expect(session_account.progress_percentage).to eq(67)
      end
    end
  end

  describe 'status query methods', integration: true do
    subject(:session_account) { build(:sync_session_account, status: status) }

    describe '#processing?', integration: true do
      context 'when status is processing' do
        let(:status) { 'processing' }
        it { expect(session_account).to be_processing }
      end

      context 'when status is not processing' do
        let(:status) { 'pending' }
        it { expect(session_account).not_to be_processing }
      end
    end

    describe '#completed?', integration: true do
      context 'when status is completed' do
        let(:status) { 'completed' }
        it { expect(session_account).to be_completed }
      end

      context 'when status is not completed' do
        let(:status) { 'processing' }
        it { expect(session_account).not_to be_completed }
      end
    end

    describe '#failed?', integration: true do
      context 'when status is failed' do
        let(:status) { 'failed' }
        it { expect(session_account).to be_failed }
      end

      context 'when status is not failed' do
        let(:status) { 'processing' }
        it { expect(session_account).not_to be_failed }
      end
    end

    describe '#pending?', integration: true do
      context 'when status is pending' do
        let(:status) { 'pending' }
        it { expect(session_account).to be_pending }
      end

      context 'when status is not pending' do
        let(:status) { 'processing' }
        it { expect(session_account).not_to be_pending }
      end
    end

    describe '#waiting?', integration: true do
      context 'when status is waiting' do
        let(:status) { 'waiting' }
        it { expect(session_account).to be_waiting }
      end

      context 'when status is not waiting' do
        let(:status) { 'processing' }
        it { expect(session_account).not_to be_waiting }
      end
    end
  end

  describe 'state transition methods', integration: true do
    let(:sync_session) { create(:sync_session) }
    let(:session_account) { create(:sync_session_account, sync_session: sync_session, status: 'pending') }

    describe '#start_processing!', integration: true do
      it 'changes status to processing' do
        expect { session_account.start_processing! }.to change { session_account.status }.from('pending').to('processing')
      end

      it 'persists changes' do
        session_account.start_processing!
        expect(session_account.reload).to be_processing
      end

      it 'can transition from waiting status' do
        session_account.update!(status: 'waiting')
        expect { session_account.start_processing! }.to change { session_account.status }.from('waiting').to('processing')
      end
    end

    describe '#complete!', integration: true do
      before do
        session_account.start_processing!
        allow(sync_session).to receive(:update_progress)
      end

      it 'changes status to completed' do
        expect { session_account.complete! }.to change { session_account.status }.from('processing').to('completed')
      end

      it 'calls update_progress on sync_session' do
        expect(sync_session).to receive(:update_progress)
        session_account.complete!
      end

      it 'persists changes' do
        session_account.complete!
        expect(session_account.reload).to be_completed
      end
    end

    describe '#fail!', integration: true do
      before { session_account.start_processing! }

      it 'changes status to failed' do
        expect { session_account.fail! }.to change { session_account.status }.from('processing').to('failed')
      end

      it 'stores error message when provided' do
        error_message = "IMAP connection timeout"
        session_account.fail!(error_message)
        expect(session_account.last_error).to eq(error_message)
      end

      it 'allows nil error message' do
        session_account.fail!
        expect(session_account.last_error).to be_nil
      end

      it 'persists changes' do
        session_account.fail!("Error")
        reloaded = session_account.reload
        expect(reloaded).to be_failed
        expect(reloaded.last_error).to eq("Error")
      end
    end
  end

  describe '#update_progress', integration: true do
    let(:sync_session) { create(:sync_session, total_emails: 100, processed_emails: 50, detected_expenses: 10) }
    let(:session_account) { create(:sync_session_account, sync_session: sync_session, total_emails: 0, processed_emails: 0, detected_expenses: 0) }

    before do
      allow(sync_session).to receive(:update_progress)
    end

    it 'updates processed_emails' do
      expect { session_account.update_progress(25, 100, 5) }.to change { session_account.processed_emails }.from(0).to(25)
    end

    it 'updates total_emails' do
      expect { session_account.update_progress(25, 100, 5) }.to change { session_account.total_emails }.from(0).to(100)
    end

    it 'increments detected_expenses' do
      expect { session_account.update_progress(25, 100, 5) }.to change { session_account.detected_expenses }.from(0).to(5)
    end

    it 'calls update_progress on sync_session' do
      expect(sync_session).to receive(:update_progress)
      session_account.update_progress(25, 100, 5)
    end

    it 'persists changes' do
      session_account.update_progress(30, 120, 8)
      reloaded = session_account.reload
      expect(reloaded.processed_emails).to eq(30)
      expect(reloaded.total_emails).to eq(120)
      expect(reloaded.detected_expenses).to eq(8)
    end

    context 'when called multiple times' do
      it 'accumulates detected_expenses' do
        session_account.update_progress(10, 50, 3)
        session_account.update_progress(20, 50, 2)
        session_account.update_progress(30, 50, 4)

        expect(session_account.detected_expenses).to eq(9) # 3 + 2 + 4
        expect(session_account.processed_emails).to eq(30)
        expect(session_account.total_emails).to eq(50)
      end
    end

    context 'with default detected parameter' do
      it 'does not increment detected_expenses when not provided' do
        expect { session_account.update_progress(25, 100) }.not_to change { session_account.detected_expenses }
      end
    end
  end

  describe 'edge cases and error handling', integration: true do
    describe 'concurrent updates', integration: true do
      let(:sync_session) { create(:sync_session) }
      let(:session_account) { create(:sync_session_account, sync_session: sync_session, status: 'processing') }

      it 'handles concurrent updates through lock_version' do
        # Mock the sync_session update_progress to avoid DB issues
        allow(sync_session).to receive(:update_progress)

        # Test that lock_version is properly incremented
        original_lock_version = session_account.lock_version

        session_account.complete!

        expect(session_account.lock_version).to eq(original_lock_version + 1)
        expect(session_account).to be_completed
      end
    end

    describe 'orphaned records', integration: true do
      let(:session_account) { create(:sync_session_account) }

      it 'is destroyed when sync_session is destroyed' do
        sync_session = session_account.sync_session
        expect { sync_session.destroy }.to change { SyncSessionAccount.count }.by(-1)
      end

      it 'is destroyed when email_account is destroyed' do
        email_account = session_account.email_account
        expect { email_account.destroy }.to change { SyncSessionAccount.count }.by(-1)
      end
    end
  end

  describe 'factory', integration: true do
    it 'has a valid factory' do
      expect(build(:sync_session_account)).to be_valid
    end

    it 'has a processing factory trait' do
      account = build(:sync_session_account, :processing)
      expect(account).to be_processing
      expect(account.total_emails).to eq(50)
      expect(account.processed_emails).to eq(10)
    end

    it 'has a completed factory trait' do
      account = build(:sync_session_account, :completed)
      expect(account).to be_completed
      expect(account.total_emails).to eq(50)
      expect(account.processed_emails).to eq(50)
      expect(account.detected_expenses).to eq(8)
    end

    it 'has a failed factory trait' do
      account = build(:sync_session_account, :failed)
      expect(account).to be_failed
      expect(account.last_error).to eq("IMAP connection failed")
    end
  end

  describe 'integration with sync_session', integration: true do
    let(:sync_session) { create(:sync_session) }
    let!(:account1) { create(:sync_session_account, sync_session: sync_session) }
    let!(:account2) { create(:sync_session_account, sync_session: sync_session) }

    it 'updates parent sync_session progress when completing' do
      allow(sync_session).to receive(:update_progress)

      account1.update_progress(50, 100, 10)
      account1.complete!

      expect(sync_session).to have_received(:update_progress).at_least(:twice)
    end
  end
end
