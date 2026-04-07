# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Services::Email::SyncService, 'Conflict Detection and Resolution', unit: true do
  let(:service) { described_class.new(options) }
  let(:options) { {} }
  let(:mock_time) { Time.zone.parse('2024-01-15 16:45:00') }
  let(:sync_session) { instance_double(SyncSession, id: 42) }

  before do
    allow(Time).to receive(:current).and_return(mock_time)
  end

  describe '#detect_conflicts' do
    context 'without a sync session' do
      it 'returns an empty array' do
        expect(service.detect_conflicts).to eq([])
      end

      it 'does not query the database' do
        expect(Expense).not_to receive(:where)
        service.detect_conflicts
      end
    end

    context 'with a sync session' do
      let(:service) do
        svc = described_class.new(options)
        svc.instance_variable_set(:@sync_session, sync_session)
        svc
      end

      let(:expense1) do
        instance_double(Expense,
          id: 1,
          amount: BigDecimal('100.50'),
          transaction_date: Date.parse('2024-01-15'),
          merchant_name: 'Supermercado ABC',
          description: 'Compra en Supermercado ABC',
          currency: 'crc',
          email_account_id: 7
        )
      end

      let(:expense2) do
        instance_double(Expense,
          id: 2,
          amount: BigDecimal('100.50'),
          transaction_date: Date.parse('2024-01-15'),
          merchant_name: 'Supermercado ABC',
          description: 'Compra Supermercado ABC',
          currency: 'crc',
          email_account_id: 7
        )
      end

      let(:conflict_detection_service) do
        instance_double(Services::ConflictDetectionService)
      end

      before do
        allow(Services::ConflictDetectionService)
          .to receive(:new).with(sync_session).and_return(conflict_detection_service)
      end

      it 'returns empty array when no recent expenses exist' do
        allow(Expense).to receive(:where)
          .with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return([])

        expect(service.detect_conflicts).to eq([])
        expect(conflict_detection_service).not_to receive(:detect_conflicts_batch)
      end

      it 'delegates to ConflictDetectionService#detect_conflicts_batch' do
        allow(Expense).to receive(:where)
          .with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return([ expense1, expense2 ])

        expected_data = [
          {
            id: 1,
            amount: BigDecimal('100.50'),
            transaction_date: Date.parse('2024-01-15'),
            merchant_name: 'Supermercado ABC',
            description: 'Compra en Supermercado ABC',
            currency: 'crc',
            email_account_id: 7
          },
          {
            id: 2,
            amount: BigDecimal('100.50'),
            transaction_date: Date.parse('2024-01-15'),
            merchant_name: 'Supermercado ABC',
            description: 'Compra Supermercado ABC',
            currency: 'crc',
            email_account_id: 7
          }
        ]

        mock_conflicts = [ instance_double(SyncConflict) ]
        expect(conflict_detection_service)
          .to receive(:detect_conflicts_batch).with(expected_data)
          .and_return(mock_conflicts)

        result = service.detect_conflicts

        expect(result).to eq(mock_conflicts)
      end

      it 'passes the correct time window (last hour) to the expense query' do
        expect(Expense).to receive(:where)
          .with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return([])

        service.detect_conflicts
      end

      it 'returns whatever ConflictDetectionService returns' do
        allow(Expense).to receive(:where).and_return([ expense1 ])

        returned_conflicts = [
          instance_double(SyncConflict, id: 10),
          instance_double(SyncConflict, id: 11)
        ]

        allow(conflict_detection_service)
          .to receive(:detect_conflicts_batch)
          .and_return(returned_conflicts)

        expect(service.detect_conflicts).to eq(returned_conflicts)
      end
    end
  end

  describe '#resolve_conflicts' do
    context 'without a sync session' do
      it 'returns zero counts' do
        result = service.resolve_conflicts

        expect(result).to eq({ resolved: 0, total: 0 })
      end
    end

    context 'with a sync session' do
      let(:service) do
        svc = described_class.new(options)
        svc.instance_variable_set(:@sync_session, sync_session)
        svc
      end

      let(:conflict_detection_service) do
        instance_double(Services::ConflictDetectionService)
      end

      let(:sync_conflicts_relation) do
        double('sync_conflicts', count: 3)
      end

      before do
        allow(Services::ConflictDetectionService)
          .to receive(:new).with(sync_session).and_return(conflict_detection_service)
        allow(sync_session).to receive(:sync_conflicts).and_return(sync_conflicts_relation)
      end

      it 'delegates to ConflictDetectionService#auto_resolve_obvious_duplicates' do
        expect(conflict_detection_service)
          .to receive(:auto_resolve_obvious_duplicates).and_return(2)

        result = service.resolve_conflicts

        expect(result[:resolved]).to eq(2)
        expect(result[:total]).to eq(3)
      end

      it 'returns resolved count from the service and total from session' do
        allow(conflict_detection_service)
          .to receive(:auto_resolve_obvious_duplicates).and_return(1)
        allow(sync_conflicts_relation).to receive(:count).and_return(5)

        result = service.resolve_conflicts

        expect(result).to eq({ resolved: 1, total: 5 })
      end

      it 'returns zero counts for unsupported strategies' do
        result = service.resolve_conflicts([], strategy: :keep_oldest)

        expect(result).to eq({ resolved: 0, total: 0 })
        expect(conflict_detection_service).not_to receive(:auto_resolve_obvious_duplicates)
      end

      it 'accepts and ignores legacy conflicts array argument' do
        legacy_conflicts = [
          { type: 'duplicate', expenses: [ 1, 2 ], confidence: 0.8 }
        ]

        expect(conflict_detection_service)
          .to receive(:auto_resolve_obvious_duplicates).and_return(1)

        result = service.resolve_conflicts(legacy_conflicts)

        expect(result[:resolved]).to eq(1)
      end

      it 'handles empty conflicts gracefully' do
        expect(conflict_detection_service)
          .to receive(:auto_resolve_obvious_duplicates).and_return(0)
        allow(sync_conflicts_relation).to receive(:count).and_return(0)

        result = service.resolve_conflicts([])

        expect(result).to eq({ resolved: 0, total: 0 })
      end
    end
  end

  describe 'integrated conflict workflow' do
    let(:options) { { detect_conflicts: true, auto_resolve: true } }
    let(:active_accounts) { double('ActiveRecord::Relation', count: 2) }

    before do
      allow(EmailAccount).to receive(:active).and_return(active_accounts)
      allow(ProcessEmailsJob).to receive(:perform_later)
    end

    it 'calls detect_conflicts and resolve_conflicts in sync_all flow' do
      expect(service).to receive(:detect_conflicts)
      expect(service).to receive(:resolve_conflicts).with(no_args)

      result = service.sync_emails

      expect(result[:success]).to be true
    end

    it 'calls detect_conflicts but not resolve_conflicts when auto_resolve is false' do
      service = described_class.new(detect_conflicts: true, auto_resolve: false)

      expect(service).to receive(:detect_conflicts)
      expect(service).not_to receive(:resolve_conflicts)

      allow(EmailAccount).to receive(:active).and_return(active_accounts)
      allow(ProcessEmailsJob).to receive(:perform_later)

      result = service.sync_emails

      expect(result[:success]).to be true
    end

    it 'skips conflict detection entirely when not enabled' do
      service = described_class.new(detect_conflicts: false)

      expect(service).not_to receive(:detect_conflicts)
      expect(service).not_to receive(:resolve_conflicts)

      allow(EmailAccount).to receive(:active).and_return(active_accounts)
      allow(ProcessEmailsJob).to receive(:perform_later)

      result = service.sync_emails

      expect(result[:success]).to be true
    end
  end
end
