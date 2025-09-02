# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Email::SyncService, 'Conflict Detection and Resolution', unit: true do
  let(:service) { described_class.new(options) }
  let(:options) { {} }
  let(:mock_time) { Time.zone.parse('2024-01-15 16:45:00') }

  before do
    allow(Time).to receive(:current).and_return(mock_time)
  end

  describe '#detect_conflicts' do
    let(:expense1) do
      instance_double(Expense,
        id: 1,
        transaction_date: Date.parse('2024-01-15'),
        amount: BigDecimal('100.50'),
        description: 'Compra en Supermercado ABC',
        created_at: mock_time - 30.minutes
      )
    end

    let(:expense2) do
      instance_double(Expense,
        id: 2,
        transaction_date: Date.parse('2024-01-15'),
        amount: BigDecimal('100.50'),
        description: 'Compra Supermercado ABC',
        created_at: mock_time - 25.minutes
      )
    end

    let(:expense3) do
      instance_double(Expense,
        id: 3,
        transaction_date: Date.parse('2024-01-15'),
        amount: BigDecimal('100.51'),
        description: 'Pago de servicios',
        created_at: mock_time - 20.minutes
      )
    end

    let(:expense4) do
      instance_double(Expense,
        id: 4,
        transaction_date: Date.parse('2024-01-14'),
        amount: BigDecimal('100.50'),
        description: 'Compra en Supermercado ABC',
        created_at: mock_time - 15.minutes
      )
    end

    before do
      allow(expense1).to receive(:amount).and_return(BigDecimal('100.50'))
      allow(expense2).to receive(:amount).and_return(BigDecimal('100.50'))
      allow(expense3).to receive(:amount).and_return(BigDecimal('100.51'))
      allow(expense4).to receive(:amount).and_return(BigDecimal('100.50'))
    end

    context 'with recent expenses' do
      before do
        # Default empty result for Expense.where
        allow(Expense).to receive(:where).with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return([])
      end

      it 'detects duplicates with same date and amount' do
        expenses = [ expense1, expense2 ]
        expense_relation = double('expense_relation')

        allow(Expense).to receive(:where).and_return(expense_relation)
        allow(expense_relation).to receive(:group_by) do |&block|
          grouped = {}
          expenses.each do |exp|
            key = block.call(exp)
            grouped[key] ||= []
            grouped[key] << exp
          end
          grouped
        end

        conflicts = service.detect_conflicts

        expect(conflicts).to include(
          hash_including(
            type: 'duplicate',
            expenses: [ 1, 2 ],
            confidence: 0.8
          )
        )
      end

      it 'does not detect conflicts for different dates' do
        expenses = [ expense1, expense4 ]
        expense_relation = double('expense_relation')

        allow(Expense).to receive(:where).and_return(expense_relation)
        allow(expense_relation).to receive(:group_by) do |&block|
          grouped = {}
          expenses.each do |exp|
            key = block.call(exp)
            grouped[key] ||= []
            grouped[key] << exp
          end
          grouped
        end

        conflicts = service.detect_conflicts

        expect(conflicts).to be_empty
      end

      it 'groups by rounded amounts to handle floating point precision' do
        expense_with_precision = instance_double(Expense,
          id: 5,
          transaction_date: Date.parse('2024-01-15'),
          amount: BigDecimal('100.504999999'),
          description: 'Compra en Supermercado ABC',  # Same description as expense1
          created_at: mock_time - 10.minutes
        )
        allow(expense_with_precision).to receive(:amount).and_return(BigDecimal('100.504999999'))

        expenses = [ expense1, expense_with_precision ]

        allow(Expense).to receive(:where).with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return(expenses)

        conflicts = service.detect_conflicts

        # Should group together as both round to 100.50
        expect(conflicts.length).to eq(1)
      end

      it 'handles empty expense list' do
        allow(Expense).to receive(:where).with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return([])

        conflicts = service.detect_conflicts

        expect(conflicts).to eq([])
      end

      it 'only creates conflicts for groups with 2+ expenses' do
        expenses = [ expense1 ] # Single expense

        allow(Expense).to receive(:where).with(created_at: (mock_time - 1.hour)..mock_time)
          .and_return(expenses)

        conflicts = service.detect_conflicts

        expect(conflicts).to be_empty
      end
    end

    describe '#similar_descriptions?' do
      it 'returns true for highly similar descriptions' do
        result = service.send(:similar_descriptions?,
          'Compra en Supermercado ABC',
          'Compra Supermercado ABC'
        )
        expect(result).to be true
      end

      it 'returns true for descriptions with common significant words' do
        result = service.send(:similar_descriptions?,
          'Pago de factura electricidad CNFL',
          'CNFL pago electricidad mensual'
        )
        expect(result).to be true
      end

      it 'returns false for completely different descriptions' do
        result = service.send(:similar_descriptions?,
          'Compra en supermercado',
          'Pago de servicios'
        )
        expect(result).to be false
      end

      it 'returns false when one description is nil' do
        result = service.send(:similar_descriptions?, nil, 'Some description')
        expect(result).to be false

        result = service.send(:similar_descriptions?, 'Some description', nil)
        expect(result).to be false
      end

      it 'returns false when both descriptions are nil' do
        result = service.send(:similar_descriptions?, nil, nil)
        expect(result).to be false
      end

      it 'is case insensitive' do
        result = service.send(:similar_descriptions?,
          'COMPRA SUPERMERCADO',
          'compra supermercado'
        )
        expect(result).to be true
      end

      it 'ignores punctuation and special characters' do
        result = service.send(:similar_descriptions?,
          'Compra-en-Supermercado!!!',
          'Compra en Supermercado...'
        )
        expect(result).to be true
      end

      it 'calculates similarity based on word overlap' do
        # 2 common words out of 3 minimum = 0.67 < 0.7 threshold
        result = service.send(:similar_descriptions?,
          'Compra en tienda',
          'Compra en supermercado grande'
        )
        expect(result).to be false

        # 3 common words out of 3 minimum = 1.0 > 0.7 threshold
        result = service.send(:similar_descriptions?,
          'Pago servicio agua',
          'Pago servicio agua mensual'
        )
        expect(result).to be true
      end

      it 'handles empty descriptions after word extraction' do
        result = service.send(:similar_descriptions?, '!!!', '...')
        expect(result).to be false
      end
    end
  end

  describe '#resolve_conflicts' do
    let(:expense1) { instance_double(Expense, id: 10, created_at: mock_time - 2.hours) }
    let(:expense2) { instance_double(Expense, id: 11, created_at: mock_time - 1.hour) }
    let(:expense3) { instance_double(Expense, id: 12, created_at: mock_time - 30.minutes) }

    let(:conflicts) do
      [
        { type: 'duplicate', expenses: [ 10, 11 ], confidence: 0.8 },
        { type: 'duplicate', expenses: [ 11, 12 ], confidence: 0.9 }
      ]
    end

    context 'with keep_newest strategy' do
      it 'keeps the most recently created expense' do
        allow(Expense).to receive(:find).with([ 10, 11 ]).and_return([ expense1, expense2 ])
        allow(Expense).to receive(:find).with([ 11, 12 ]).and_return([ expense2, expense3 ])

        # First conflict: expense2 is newer than expense1
        expect(expense1).to receive(:reload).and_return(expense1)
        expect(expense1).to receive(:update!).with(
          status: 'duplicate'
        )

        # Second conflict: expense3 is newer than expense2
        expect(expense2).to receive(:reload).and_return(expense2)
        expect(expense2).to receive(:update!).with(
          status: 'duplicate'
        )

        result = service.resolve_conflicts(conflicts)

        expect(result[:resolved]).to eq(2)
        expect(result[:total]).to eq(2)
      end

      it 'does not mark the keeper expense as duplicate' do
        allow(Expense).to receive(:find).with([ 10, 11 ]).and_return([ expense1, expense2 ])

        expect(expense1).to receive(:reload).and_return(expense1)
        expect(expense1).to receive(:update!).with(
          status: 'duplicate'
        )
        expect(expense2).not_to receive(:update!)

        service.resolve_conflicts([ conflicts.first ])
      end

      it 'handles StaleObjectError gracefully' do
        allow(Expense).to receive(:find).with([ 10, 11 ]).and_return([ expense1, expense2 ])

        expect(expense1).to receive(:reload).and_raise(
          ActiveRecord::StaleObjectError.new(expense1, 'update')
        )

        expect(Rails.logger).to receive(:warn).with(
          'Skipped marking expense 10 as duplicate due to concurrent modification'
        )

        result = service.resolve_conflicts([ conflicts.first ])

        expect(result[:resolved]).to eq(1) # Still counts as resolved
        expect(result[:total]).to eq(1)
      end
    end

    context 'with different conflict types' do
      it 'only processes duplicate type conflicts' do
        mixed_conflicts = [
          { type: 'duplicate', expenses: [ 10, 11 ], confidence: 0.8 },
          { type: 'mismatch', expenses: [ 12, 13 ], confidence: 0.7 },
          { type: 'unknown', expenses: [ 14, 15 ], confidence: 0.9 }
        ]

        allow(Expense).to receive(:find).with([ 10, 11 ]).and_return([ expense1, expense2 ])
        allow(expense1).to receive(:reload).and_return(expense1)
        allow(expense1).to receive(:update!)

        result = service.resolve_conflicts(mixed_conflicts)

        expect(result[:resolved]).to eq(1)
        expect(result[:total]).to eq(3)
      end
    end

    context 'with custom strategy' do
      it 'ignores unsupported strategies' do
        # Current implementation only supports keep_newest
        # Passing keep_oldest should result in no resolution
        result = service.resolve_conflicts(conflicts, strategy: :keep_oldest)

        # Service ignores unsupported strategies
        expect(result[:resolved]).to eq(0)
        expect(result[:total]).to eq(2)
      end
    end

    context 'error handling' do
      it 'continues processing after individual conflict errors' do
        allow(Expense).to receive(:find).with([ 10, 11 ]).and_raise(ActiveRecord::RecordNotFound)
        allow(Expense).to receive(:find).with([ 11, 12 ]).and_return([ expense2, expense3 ])

        expect(expense2).to receive(:reload).and_return(expense2)
        expect(expense2).to receive(:update!)

        result = service.resolve_conflicts(conflicts)

        expect(result[:resolved]).to eq(1)
        expect(result[:total]).to eq(2)
      end

      it 'handles empty conflicts array' do
        result = service.resolve_conflicts([])

        expect(result[:resolved]).to eq(0)
        expect(result[:total]).to eq(0)
      end

      it 'handles conflicts with missing expense IDs' do
        invalid_conflicts = [
          { type: 'duplicate', expenses: [], confidence: 0.8 },
          { type: 'duplicate', expenses: [ 999 ], confidence: 0.9 }
        ]

        allow(Expense).to receive(:find).with([]).and_raise(ActiveRecord::RecordNotFound)
        allow(Expense).to receive(:find).with([ 999 ]).and_raise(ActiveRecord::RecordNotFound)

        result = service.resolve_conflicts(invalid_conflicts)

        expect(result[:resolved]).to eq(0)
        expect(result[:total]).to eq(2)
      end
    end

    context 'performance considerations' do
      it 'uses reload before update to prevent stale data' do
        allow(Expense).to receive(:find).with([ 10, 11 ]).and_return([ expense1, expense2 ])

        expect(expense1).to receive(:reload).ordered.and_return(expense1)
        expect(expense1).to receive(:update!).ordered

        service.resolve_conflicts([ conflicts.first ])
      end

      it 'processes conflicts sequentially to avoid deadlocks' do
        call_order = []

        allow(Expense).to receive(:find) do |ids|
          call_order << ids
          if ids == [ 10, 11 ]
            [ expense1, expense2 ]
          else
            [ expense2, expense3 ]
          end
        end

        allow(expense1).to receive(:reload).and_return(expense1)
        allow(expense1).to receive(:update!)
        allow(expense2).to receive(:reload).and_return(expense2)
        allow(expense2).to receive(:update!)

        service.resolve_conflicts(conflicts)

        expect(call_order).to eq([ [ 10, 11 ], [ 11, 12 ] ])
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

    it 'detects and resolves conflicts in sync_all flow' do
      conflicts = [
        { type: 'duplicate', expenses: [ 1, 2 ], confidence: 0.85 }
      ]

      expect(service).to receive(:detect_conflicts).and_return(conflicts)
      expect(service).to receive(:resolve_conflicts).with(conflicts)

      result = service.sync_emails

      expect(result[:success]).to be true
    end

    it 'detects but does not resolve when auto_resolve is false' do
      service = described_class.new(detect_conflicts: true, auto_resolve: false)
      conflicts = [ { type: 'duplicate', expenses: [ 1, 2 ], confidence: 0.85 } ]

      expect(service).to receive(:detect_conflicts).and_return(conflicts)
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
