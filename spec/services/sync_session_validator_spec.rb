require 'rails_helper'

RSpec.describe SyncSessionValidator, integration: true do
  let(:validator) { described_class.new }

  before(:each) do
    # Clean up sync sessions to ensure test isolation
    SyncMetric.delete_all if defined?(SyncMetric)
    SyncSessionAccount.delete_all
    SyncSession.delete_all
  end

  describe '#validate!', integration: true do
    context 'when no active syncs exist and rate limit not exceeded' do
      before do
        allow(validator).to receive(:active_sync_exists?).and_return(false)
        allow(validator).to receive(:rate_limit_exceeded?).and_return(false)
      end

      it 'returns true' do
        expect(validator.validate!).to be true
      end
    end

    context 'when active sync limit is exceeded' do
      before do
        create(:sync_session, status: 'running')
      end

      it 'raises SyncLimitExceeded error' do
        expect { validator.validate! }.to raise_error(
          SyncSessionValidator::SyncLimitExceeded,
          "Ya hay una sincronización activa. Espera a que termine antes de iniciar otra."
        )
      end
    end

    context 'when rate limit is exceeded' do
      before do
        # Ensure no active syncs exist first (validator checks this first)
        # Create 3 completed sync sessions in the last 5 minutes to trigger rate limit
        3.times { create(:sync_session, status: 'completed', created_at: 2.minutes.ago) }
      end

      it 'raises RateLimitExceeded error' do
        expect { validator.validate! }.to raise_error(
          SyncSessionValidator::RateLimitExceeded,
          "Has alcanzado el límite de sincronizaciones. Intenta nuevamente en unos minutos."
        )
      end
    end
  end

  describe '#can_create_sync?', integration: true do
    context 'when conditions are favorable' do
      before do
        allow(validator).to receive(:active_sync_exists?).and_return(false)
        allow(validator).to receive(:rate_limit_exceeded?).and_return(false)
      end

      it 'returns true' do
        expect(validator.can_create_sync?).to be true
      end
    end

    context 'when active sync exists' do
      before do
        create(:sync_session, status: 'running')
      end

      it 'returns false' do
        expect(validator.can_create_sync?).to be false
      end
    end

    context 'when rate limit exceeded' do
      before do
        3.times { create(:sync_session, created_at: 2.minutes.ago) }
      end

      it 'returns false' do
        expect(validator.can_create_sync?).to be false
      end
    end
  end

  describe '#active_sync_exists?', integration: true do
    context 'with no active syncs' do
      it 'returns false' do
        expect(validator.active_sync_exists?).to be false
      end
    end

    context 'with pending sync' do
      before { create(:sync_session, status: 'pending') }

      it 'returns true' do
        expect(validator.active_sync_exists?).to be true
      end
    end

    context 'with running sync' do
      before { create(:sync_session, status: 'running') }

      it 'returns true' do
        expect(validator.active_sync_exists?).to be true
      end
    end

    context 'with completed sync' do
      before { create(:sync_session, status: 'completed') }

      it 'returns false' do
        expect(validator.active_sync_exists?).to be false
      end
    end
  end

  describe '#recent_sync_count', integration: true do
    context 'with no recent syncs' do
      it 'returns 0' do
        expect(validator.recent_sync_count).to eq(0)
      end
    end

    context 'with syncs in different time windows' do
      before do
        # Clean up any existing sync sessions for predictable test
        SyncSession.destroy_all

        # Old sync (outside window)
        create(:sync_session, created_at: 10.minutes.ago)
        # Recent syncs (inside window)
        create(:sync_session, created_at: 2.minutes.ago)
        create(:sync_session, created_at: 1.minute.ago)
      end

      it 'counts only syncs within the rate limit window' do
        expect(validator.recent_sync_count).to eq(2)
      end
    end
  end

  describe 'constants', integration: true do
    it 'has appropriate rate limit settings' do
      expect(described_class::RATE_LIMIT_WINDOW).to eq(5.minutes)
      expect(described_class::MAX_SYNCS_PER_WINDOW).to eq(3)
      expect(described_class::MAX_ACTIVE_SYNCS).to eq(1)
    end
  end
end
