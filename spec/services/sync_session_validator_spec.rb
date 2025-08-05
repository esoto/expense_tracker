require 'rails_helper'

RSpec.describe SyncSessionValidator do
  let(:validator) { described_class.new }

  describe '#validate!' do
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
          "Maximum number of active syncs reached"
        )
      end
    end

    context 'when rate limit is exceeded' do
      before do
        # Create 3 completed sync sessions in the last 5 minutes
        3.times { create(:sync_session, status: 'completed', created_at: 2.minutes.ago) }
      end

      it 'raises RateLimitExceeded error' do
        expect { validator.validate! }.to raise_error(
          SyncSessionValidator::RateLimitExceeded,
          "Rate limit exceeded"
        )
      end
    end
  end

  describe '#can_create_sync?' do
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

  describe '#active_sync_exists?' do
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

  describe '#recent_sync_count' do
    context 'with no recent syncs' do
      it 'returns 0' do
        expect(validator.recent_sync_count).to eq(0)
      end
    end

    context 'with syncs in different time windows' do
      before do
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

  describe 'constants' do
    it 'has appropriate rate limit settings' do
      expect(described_class::RATE_LIMIT_WINDOW).to eq(5.minutes)
      expect(described_class::MAX_SYNCS_PER_WINDOW).to eq(3)
      expect(described_class::MAX_ACTIVE_SYNCS).to eq(1)
    end
  end
end
