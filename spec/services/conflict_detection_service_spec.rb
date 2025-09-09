require 'rails_helper'

RSpec.describe ConflictDetectionService, integration: true do
  let(:sync_session) { create(:sync_session) }
  let(:email_account) { create(:email_account) }
  let(:service) { described_class.new(sync_session) }

  describe '#detect_conflict_for_expense', integration: true do
    let(:existing_expense) do
      create(:expense,
        email_account: email_account,
        amount: 100.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase at Test Store',
        status: 'processed'
      )
    end

    let(:new_expense_data) do
      {
        email_account_id: email_account.id,
        amount: 100.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase at Test Store',
        currency: 'crc'
      }
    end

    context 'when exact duplicate exists' do
      before { existing_expense }

      it 'creates a duplicate conflict' do
        conflict = service.detect_conflict_for_expense(new_expense_data)

        expect(conflict).to be_present
        expect(conflict.conflict_type).to eq('duplicate')
        expect(conflict.similarity_score).to be >= 90
      end

      it 'associates with the existing expense' do
        conflict = service.detect_conflict_for_expense(new_expense_data)
        expect(conflict.existing_expense).to eq(existing_expense)
      end
    end

    context 'when similar expense exists' do
      before do
        existing_expense.update(amount: 95.00) # Slightly different amount
      end

      it 'creates a similar conflict' do
        conflict = service.detect_conflict_for_expense(new_expense_data)

        expect(conflict).to be_present
        expect(conflict.conflict_type).to eq('similar')
        expect(conflict.similarity_score).to be_between(70, 90)
      end
    end

    context 'when no similar expense exists' do
      before do
        existing_expense.update(
          amount: 500.00,
          transaction_date: Date.today - 30.days,
          merchant_name: 'Different Store'
        )
      end

      it 'returns nil' do
        conflict = service.detect_conflict_for_expense(new_expense_data)
        expect(conflict).to be_nil
      end
    end

    context 'when multiple candidates exist' do
      let!(:exact_match) do
        create(:expense,
          email_account: email_account,
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'Test Store',
          status: 'processed'
        )
      end

      let!(:partial_match) do
        create(:expense,
          email_account: email_account,
          amount: 99.00,
          transaction_date: Date.today,
          merchant_name: 'Test Store',
          status: 'processed'
        )
      end

      it 'selects the best match' do
        conflict = service.detect_conflict_for_expense(new_expense_data)
        expect(conflict.existing_expense).to eq(exact_match)
      end
    end
  end

  describe '#detect_conflicts_batch', integration: true do
    let(:new_expenses_data) do
      [
        {
          email_account_id: email_account.id,
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'Store A',
          currency: 'crc',
          description: 'Purchase at Store A'
        },
        {
          email_account_id: email_account.id,
          amount: 200.00,
          transaction_date: Date.today,
          merchant_name: 'Store B',
          currency: 'crc',
          description: 'Purchase at Store B'
        }
      ]
    end

    context 'when some expenses have conflicts' do
      before do
        create(:expense,
          email_account: email_account,
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'Store A',
          status: 'processed',
          currency: 'crc',
          description: 'Purchase at Store A'
        )
      end

      it 'returns array of conflicts' do
        conflicts = service.detect_conflicts_batch(new_expenses_data)

        expect(conflicts).to be_an(Array)
        expect(conflicts.size).to eq(1)
        expect(conflicts.first).to be_a(SyncConflict)
      end
    end
  end

  describe '#auto_resolve_obvious_duplicates', integration: true do
    # Create actual expenses for the conflicts
    let!(:existing_expense_for_high) { create(:expense, email_account: email_account) }
    let!(:new_expense_for_high) { create(:expense, email_account: email_account, status: :pending) }

    let!(:existing_expense_for_low) { create(:expense, email_account: email_account) }
    let!(:new_expense_for_low) { create(:expense, email_account: email_account, status: :pending) }

    let!(:high_confidence_conflict) do
      conflict = create(:sync_conflict,
        sync_session: sync_session,
        existing_expense: existing_expense_for_high,
        new_expense: new_expense_for_high,
        similarity_score: 98.0,
        conflict_type: 'duplicate',
        status: 'pending'
      )
      # Force the score to ensure it's set correctly
      conflict.update_column(:similarity_score, 98.0)
      conflict
    end

    let!(:low_confidence_conflict) do
      conflict = create(:sync_conflict,
        sync_session: sync_session,
        existing_expense: existing_expense_for_low,
        new_expense: new_expense_for_low,
        similarity_score: 85.0,
        conflict_type: 'duplicate',
        status: 'pending'
      )
      # Force the score to ensure it's set correctly
      conflict.update_column(:similarity_score, 85.0)
      conflict
    end

    it 'resolves only high-confidence duplicates' do
      resolved_count = service.auto_resolve_obvious_duplicates

      expect(resolved_count).to eq(1)
      expect(high_confidence_conflict.reload.status).to eq('resolved')
      expect(low_confidence_conflict.reload.status).to eq('pending')

      # Verify the new expense was marked as duplicate
      expect(new_expense_for_high.reload.status).to eq('duplicate')
      expect(new_expense_for_low.reload.status).to eq('pending')
    end

    it 'uses keep_existing resolution action' do
      service.auto_resolve_obvious_duplicates

      expect(high_confidence_conflict.reload.resolution_action).to eq('keep_existing')
    end
  end

  describe 'similarity calculation', integration: true do
    let(:expense1) do
      build(:expense,
        amount: 100.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase',
        currency: 'crc'
      )
    end

    context '#calculate_similarity' do
      it 'returns 100 for identical expenses' do
        expense_data = {
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'Test Store',
          description: 'Purchase',
          currency: 'crc'
        }

        score = service.send(:calculate_similarity, expense1, expense_data)
        expect(score).to be >= 95
      end

      it 'returns lower score for different amounts' do
        expense_data = {
          amount: 150.00,
          transaction_date: Date.today,
          merchant_name: 'Test Store',
          description: 'Purchase',
          currency: 'crc'
        }

        score = service.send(:calculate_similarity, expense1, expense_data)
        expect(score).to be < 90
      end

      it 'returns lower score for different dates' do
        expense_data = {
          amount: 100.00,
          transaction_date: Date.today - 5.days,
          merchant_name: 'Test Store',
          description: 'Purchase',
          currency: 'crc'
        }

        score = service.send(:calculate_similarity, expense1, expense_data)
        expect(score).to be < 100
      end
    end

    context '#string_similarity' do
      it 'returns 100 for identical strings' do
        score = service.send(:string_similarity, 'test', 'test')
        expect(score).to eq(100.0)
      end

      it 'returns 0 for empty strings' do
        score = service.send(:string_similarity, '', 'test')
        expect(score).to eq(0.0)
      end

      it 'calculates partial similarity' do
        score = service.send(:string_similarity, 'test', 'text')
        expect(score).to be_between(50, 90)
      end
    end
  end
end
