require 'rails_helper'

RSpec.describe SyncSessionPerformanceOptimizer do
  let(:email_account1) { create(:email_account) }
  let(:email_account2) { create(:email_account) }
  let(:sync_session) { create(:sync_session, :running) }

  describe '.preload_for_index' do
    let!(:session1) { create(:sync_session) }
    let!(:session2) { create(:sync_session) }

    before do
      session1.email_accounts << email_account1
      session2.email_accounts << [ email_account1, email_account2 ]
    end

    it 'returns sessions with preloaded associations' do
      sessions = described_class.preload_for_index

      # Test that associations are loaded
      expect(sessions.first.association(:email_accounts)).to be_loaded
      expect(sessions.first.association(:sync_session_accounts)).to be_loaded
    end

    it 'orders by created_at descending' do
      older_session = create(:sync_session, created_at: 2.days.ago)
      newer_session = create(:sync_session, created_at: 1.hour.ago)

      sessions = described_class.preload_for_index
      expect(sessions.first.created_at).to be > sessions.last.created_at
    end
  end

  describe '.preload_for_show' do
    let!(:account1) { create(:sync_session_account, sync_session: sync_session, email_account: email_account1) }
    let!(:account2) { create(:sync_session_account, sync_session: sync_session, email_account: email_account2) }

    it 'returns accounts with preloaded email accounts' do
      accounts = described_class.preload_for_show(sync_session)

      expect(accounts.first.association(:email_account)).to be_loaded
    end

    it 'orders by created_at' do
      newer_account = create(:sync_session_account,
                           sync_session: sync_session,
                           email_account: create(:email_account),
                           created_at: 1.hour.from_now)

      accounts = described_class.preload_for_show(sync_session)
      expect(accounts.last).to eq(newer_account)
    end
  end

  describe '.batch_update_progress' do
    let!(:session1) { create(:sync_session) }
    let!(:session2) { create(:sync_session) }
    let!(:account1) do
      create(:sync_session_account,
             sync_session: session1,
             total_emails: 100,
             processed_emails: 50,
             detected_expenses: 10)
    end
    let!(:account2) do
      create(:sync_session_account,
             sync_session: session2,
             total_emails: 200,
             processed_emails: 150,
             detected_expenses: 20)
    end

    it 'updates progress for multiple sessions' do
      described_class.batch_update_progress([ session1.id, session2.id ])

      session1.reload
      expect(session1.total_emails).to eq(100)
      expect(session1.processed_emails).to eq(50)
      expect(session1.detected_expenses).to eq(10)

      session2.reload
      expect(session2.total_emails).to eq(200)
      expect(session2.processed_emails).to eq(150)
      expect(session2.detected_expenses).to eq(20)
    end

    it 'handles empty array' do
      expect { described_class.batch_update_progress([]) }.not_to raise_error
    end
  end

  describe '.cache_key_for_session' do
    it 'returns a cache key with id and updated_at' do
      timestamp = Time.parse('2025-01-01 12:00:00 UTC')
      sync_session.update!(updated_at: timestamp)
      key = described_class.cache_key_for_session(sync_session)

      expect(key).to eq("sync_session/#{sync_session.id}/#{timestamp.to_i}")
    end
  end

  describe '.cache_key_for_status' do
    it 'returns a cache key for status' do
      key = described_class.cache_key_for_status(123)
      expect(key).to eq("sync_session_status/123")
    end
  end

  describe '.active_session_exists?' do
    it 'returns true when active session exists' do
      create(:sync_session, status: 'running')
      expect(described_class.active_session_exists?).to be true
    end

    it 'returns false when no active session exists' do
      # Clear any existing active sessions from other tests
      SyncSession.active.update_all(status: 'completed')
      # Clear the cache to ensure fresh query
      described_class.clear_active_session_cache

      create(:sync_session, status: 'completed')
      expect(described_class.active_session_exists?).to be false
    end

    it 'uses caching' do
      expect(Rails.cache).to receive(:fetch).with("active_sync_session_exists", expires_in: 30.seconds)
      described_class.active_session_exists?
    end
  end

  describe '.clear_active_session_cache' do
    it 'deletes the cache key' do
      expect(Rails.cache).to receive(:delete).with("active_sync_session_exists")
      described_class.clear_active_session_cache
    end
  end

  describe '.calculate_metrics' do
    context 'with a running session' do
      let(:sync_session) do
        create(:sync_session,
               status: 'running',
               started_at: 2.minutes.ago,
               total_emails: 100,
               processed_emails: 50)
      end

      it 'calculates performance metrics' do
        metrics = described_class.calculate_metrics(sync_session)

        expect(metrics[:duration_seconds]).to be_within(5).of(120)
        expect(metrics[:emails_per_second]).to be > 0
        expect(metrics[:average_time_per_email]).to be > 0
        expect(metrics[:estimated_completion]).to be_a(Time)
      end
    end

    context 'with no started_at' do
      let(:sync_session) { create(:sync_session, started_at: nil) }

      it 'returns empty metrics' do
        metrics = described_class.calculate_metrics(sync_session)
        expect(metrics).to eq({})
      end
    end

    context 'with zero processed emails' do
      let(:sync_session) do
        create(:sync_session,
               status: 'running',
               started_at: 1.minute.ago,
               processed_emails: 0)
      end

      it 'handles division by zero' do
        metrics = described_class.calculate_metrics(sync_session)

        expect(metrics[:emails_per_second]).to eq(0)
        expect(metrics[:average_time_per_email]).to be_nil
        expect(metrics[:estimated_completion]).to be_nil
      end
    end
  end
end
