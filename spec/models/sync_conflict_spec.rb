require 'rails_helper'

RSpec.describe SyncConflict, type: :model, integration: true do
  let(:sync_session) { create(:sync_session) }
  let(:email_account) { create(:email_account) }
  let(:existing_expense) { create(:expense, email_account: email_account, amount: 100, transaction_date: Date.today) }
  let(:new_expense) { create(:expense, email_account: email_account, amount: 100, transaction_date: Date.today, status: 'duplicate') }

  describe 'associations', integration: true do
    it { should belong_to(:existing_expense).class_name('Expense') }
    it { should belong_to(:new_expense).class_name('Expense').optional }
    it { should belong_to(:sync_session) }
    it { should have_many(:conflict_resolutions).dependent(:destroy) }
  end

  describe 'validations', integration: true do
    it { should validate_presence_of(:conflict_type) }
    it { should validate_presence_of(:status) }

    it 'validates similarity_score range' do
      conflict = build(:sync_conflict, similarity_score: 101)
      expect(conflict).not_to be_valid

      conflict.similarity_score = -1
      expect(conflict).not_to be_valid

      conflict.similarity_score = 50
      expect(conflict).to be_valid
    end
  end

  describe 'scopes', integration: true do
    let!(:pending_conflict) { create(:sync_conflict, status: 'pending') }
    let!(:resolved_conflict) { create(:sync_conflict, status: 'resolved') }
    let!(:auto_resolved_conflict) { create(:sync_conflict, status: 'auto_resolved') }

    describe '.unresolved', integration: true do
      it 'returns only pending conflicts' do
        expect(SyncConflict.unresolved).to include(pending_conflict)
        expect(SyncConflict.unresolved).not_to include(resolved_conflict, auto_resolved_conflict)
      end
    end

    describe '.resolved', integration: true do
      it 'returns resolved and auto_resolved conflicts' do
        expect(SyncConflict.resolved).to include(resolved_conflict, auto_resolved_conflict)
        expect(SyncConflict.resolved).not_to include(pending_conflict)
      end
    end
  end

  describe '#resolve!', integration: true do
    let(:conflict) { create(:sync_conflict, :with_new_expense, status: 'pending') }

    context 'with keep_existing action' do
      it 'marks new expense as duplicate' do
        conflict.resolve!('keep_existing')
        expect(conflict.new_expense.reload.status).to eq('duplicate')
      end

      it 'updates conflict status to resolved' do
        conflict.resolve!('keep_existing')
        expect(conflict.reload.status).to eq('resolved')
        expect(conflict.resolution_action).to eq('keep_existing')
      end

      it 'creates a resolution record' do
        expect {
          conflict.resolve!('keep_existing')
        }.to change(ConflictResolution, :count).by(1)
      end
    end

    context 'with keep_new action' do
      it 'marks existing expense as duplicate and new as processed' do
        conflict.resolve!('keep_new')
        expect(conflict.existing_expense.reload.status).to eq('duplicate')
        expect(conflict.new_expense.reload.status).to eq('processed')
      end
    end

    context 'with keep_both action' do
      it 'marks both expenses as processed' do
        conflict.resolve!('keep_both')
        expect(conflict.new_expense.reload.status).to eq('processed')
      end
    end
  end

  describe '#undo_last_resolution!', integration: true do
    let(:conflict) { create(:sync_conflict, :with_new_expense) }

    before do
      conflict.resolve!('keep_existing')
    end

    it 'reverts conflict to pending status' do
      conflict.undo_last_resolution!
      expect(conflict.reload.status).to eq('pending')
    end

    it 'marks the resolution as undone' do
      resolution = conflict.conflict_resolutions.last
      conflict.undo_last_resolution!
      expect(resolution.reload.undone).to be true
    end

    it 'creates an undo resolution record' do
      expect {
        conflict.undo_last_resolution!
      }.to change(ConflictResolution, :count).by(1)

      undo_resolution = conflict.conflict_resolutions.last
      expect(undo_resolution.action).to eq('undo')
    end
  end

  describe '#calculate_similarity_score', integration: true do
    let(:conflict) { build(:sync_conflict, :with_new_expense, similarity_score: nil) }

    context 'when expenses are identical' do
      before do
        conflict.new_expense.amount = conflict.existing_expense.amount
        conflict.new_expense.transaction_date = conflict.existing_expense.transaction_date
        conflict.new_expense.merchant_name = conflict.existing_expense.merchant_name
      end

      it 'calculates high similarity score' do
        conflict.save
        expect(conflict.similarity_score).to be >= 90
      end
    end

    context 'when expenses are different' do
      before do
        conflict.new_expense.amount = conflict.existing_expense.amount * 2
        conflict.new_expense.transaction_date = conflict.existing_expense.transaction_date - 10.days
        conflict.new_expense.merchant_name = 'Different Merchant'
      end

      it 'calculates low similarity score' do
        conflict.save
        expect(conflict.similarity_score).to be < 50
      end
    end
  end

  describe '#field_differences', integration: true do
    let(:conflict) do
      create(:sync_conflict,
        differences: {
          'amount' => { existing: 100, new: 150, match: false },
          'merchant_name' => { existing: 'Store A', new: 'Store A', match: true }
        }
      )
    end

    it 'returns the differences hash' do
      expect(conflict.field_differences).to eq(conflict.differences)
    end
  end

  describe '#similar_conflicts', integration: true do
    let(:email_account) { create(:email_account) }
    let(:existing_expense) { create(:expense, email_account: email_account) }
    let(:sync_session) { create(:sync_session) }
    let!(:conflict1) { create(:sync_conflict, existing_expense: existing_expense, conflict_type: 'duplicate', status: 'pending', sync_session: sync_session) }
    let!(:conflict2) { create(:sync_conflict, existing_expense: existing_expense, conflict_type: 'duplicate', status: 'pending', sync_session: sync_session) }
    let!(:different_expense_conflict) { create(:sync_conflict, conflict_type: 'duplicate', status: 'pending', sync_session: sync_session) }
    let!(:resolved_conflict) { create(:sync_conflict, existing_expense: existing_expense, conflict_type: 'duplicate', status: 'resolved', sync_session: sync_session) }

    it 'returns similar unresolved conflicts for the same existing expense' do
      similar = conflict1.similar_conflicts
      expect(similar).to include(conflict2)
      expect(similar).not_to include(conflict1) # excludes self
      expect(similar).not_to include(different_expense_conflict) # different expense
      expect(similar).not_to include(resolved_conflict) # resolved
    end
  end

  describe '#can_bulk_resolve?', integration: true do
    context 'when bulk_resolvable is true and status is pending' do
      let(:conflict) { create(:sync_conflict, bulk_resolvable: true, status: 'pending') }

      it 'returns true' do
        expect(conflict.can_bulk_resolve?).to be true
      end
    end

    context 'when bulk_resolvable is false' do
      let(:conflict) { create(:sync_conflict, bulk_resolvable: false, status: 'pending') }

      it 'returns false' do
        expect(conflict.can_bulk_resolve?).to be false
      end
    end

    context 'when status is not pending' do
      let(:conflict) { create(:sync_conflict, bulk_resolvable: true, status: 'resolved') }

      it 'returns false' do
        expect(conflict.can_bulk_resolve?).to be false
      end
    end
  end

  describe '#formatted_similarity_score', integration: true do
    context 'when similarity_score is nil' do
      let(:conflict) { create(:sync_conflict, similarity_score: nil) }

      it 'returns N/A' do
        expect(conflict.formatted_similarity_score).to eq('N/A')
      end
    end

    context 'when similarity_score is present' do
      let(:conflict) { create(:sync_conflict, similarity_score: 87.654) }

      it 'returns formatted percentage' do
        expect(conflict.formatted_similarity_score).to eq('87.7%')
      end
    end
  end

  describe 'similarity scoring edge cases', integration: true do
    let(:existing_expense) { create(:expense, amount: 100, transaction_date: Date.today, merchant_name: 'Test Store', description: 'Test Purchase') }
    let(:new_expense) { create(:expense, amount: 99.5, transaction_date: Date.today - 2.days, merchant_name: 'Test', description: 'Purchase') }
    let(:conflict) { build(:sync_conflict, existing_expense: existing_expense, new_expense: new_expense, conflict_type: 'similar', similarity_score: nil) }

    it 'handles close amount matches (within $1)' do
      conflict.save
      # Should get 30 points for amount (within $1), 10 for date (within 3 days), 10 for merchant partial match, 5 for description partial match
      # Total: 55/100 = 55%
      expect(conflict.similarity_score).to be_between(45, 55)
    end


    it 'handles partial merchant name matches' do
      new_expense.update!(amount: 200, transaction_date: existing_expense.transaction_date - 10.days, merchant_name: 'Test Store Plus', description: 'Different')
      conflict.save
      # Should get 10 points for merchant partial match
      # Total: 10/100 = 10%
      expect(conflict.similarity_score).to eq(10.0)
    end

    it 'handles partial description matches' do
      new_expense.update!(amount: 200, transaction_date: existing_expense.transaction_date - 10.days, merchant_name: 'Different Store', description: 'Test Purchase Extra')
      conflict.save
      # Should get 5 points for description partial match
      # Total: 5/100 = 5%
      expect(conflict.similarity_score).to eq(5.0)
    end
  end

  describe 'priority calculation based on conflict type and score', integration: true do
    context 'for duplicate conflicts' do
      it 'sets priority 1 for high similarity score (>=90)' do
        conflict = build(:sync_conflict, conflict_type: 'duplicate', similarity_score: 95, priority: nil)
        conflict.save
        expect(conflict.priority).to eq(1)
      end

      it 'sets priority 2 for lower similarity score (<90)' do
        conflict = build(:sync_conflict, conflict_type: 'duplicate', similarity_score: 80, priority: nil)
        conflict.save
        expect(conflict.priority).to eq(2)
      end
    end

    context 'for similar conflicts' do
      it 'sets priority 3' do
        conflict = build(:sync_conflict, conflict_type: 'similar', priority: nil)
        conflict.save
        expect(conflict.priority).to eq(3)
      end
    end

    context 'for updated conflicts' do
      it 'sets priority 4' do
        conflict = build(:sync_conflict, conflict_type: 'updated', priority: nil)
        conflict.save
        expect(conflict.priority).to eq(4)
      end
    end

    context 'for needs_review conflicts' do
      it 'sets priority 5' do
        conflict = build(:sync_conflict, conflict_type: 'needs_review', priority: nil)
        conflict.save
        expect(conflict.priority).to eq(5)
      end
    end

    context 'for unknown conflict type' do
      it 'sets priority 0' do
        conflict = build(:sync_conflict, priority: nil)
        allow(conflict).to receive(:conflict_type).and_return('unknown')
        conflict.save
        expect(conflict.priority).to eq(0)
      end
    end
  end

  describe '#resolve! with merged action', integration: true do
    let(:existing_expense) { create(:expense, amount: 100, merchant_name: 'Old Store', description: 'Old Description') }
    let(:new_expense) { create(:expense, amount: 150, merchant_name: 'New Store', description: 'New Description') }
    let(:conflict) { create(:sync_conflict, existing_expense: existing_expense, new_expense: new_expense, status: 'pending') }

    it 'merges specified fields from new expense to existing' do
      merge_data = {
        'amount' => 'new',
        'merchant_name' => 'new'
      }

      conflict.resolve!('merged', merge_data)

      existing_expense.reload
      expect(existing_expense.amount).to eq(150)
      expect(existing_expense.merchant_name).to eq('New Store')
      expect(existing_expense.description).to eq('Old Description') # unchanged
      expect(new_expense.reload.status).to eq('duplicate')
    end

    it 'handles empty merge data' do
      conflict.resolve!('merged', {})

      existing_expense.reload
      expect(existing_expense.amount).to eq(100) # unchanged
      expect(new_expense.reload.status).to eq('duplicate')
    end

    it 'ignores non-existent fields in merge data' do
      merge_data = { 'non_existent_field' => 'new' }

      expect { conflict.resolve!('merged', merge_data) }.not_to raise_error
      expect(new_expense.reload.status).to eq('duplicate')
    end
  end

  describe '#resolve! with custom action', integration: true do
    let(:existing_expense) { create(:expense, amount: 100, merchant_name: 'Old Store') }
    let(:new_expense) { create(:expense, amount: 150, merchant_name: 'New Store') }
    let(:conflict) { create(:sync_conflict, existing_expense: existing_expense, new_expense: new_expense, status: 'pending') }

    it 'applies custom field values to existing expense' do
      custom_data = {
        'existing_expense' => {
          'amount' => 200,
          'merchant_name' => 'Custom Store'
        }
      }

      conflict.resolve!('custom', custom_data)

      existing_expense.reload
      expect(existing_expense.amount).to eq(200)
      expect(existing_expense.merchant_name).to eq('Custom Store')
    end

    it 'applies custom field values to new expense' do
      custom_data = {
        'new_expense' => {
          'amount' => 300,
          'merchant_name' => 'New Custom Store'
        }
      }

      conflict.resolve!('custom', custom_data)

      new_expense.reload
      expect(new_expense.amount).to eq(300)
      expect(new_expense.merchant_name).to eq('New Custom Store')
    end

    it 'applies custom field values to both expenses' do
      custom_data = {
        'existing_expense' => {
          'amount' => 400
        },
        'new_expense' => {
          'amount' => 500
        }
      }

      conflict.resolve!('custom', custom_data)

      existing_expense.reload
      new_expense.reload
      expect(existing_expense.amount).to eq(400)
      expect(new_expense.amount).to eq(500)
    end

    it 'handles empty custom data' do
      expect { conflict.resolve!('custom', {}) }.not_to raise_error
    end

    it 'handles custom data with empty expense data' do
      custom_data = {
        'existing_expense' => {},
        'new_expense' => {}
      }

      expect { conflict.resolve!('custom', custom_data) }.not_to raise_error
    end
  end

  describe '#resolve! with custom action when new_expense is nil', integration: true do
    let(:existing_expense) { create(:expense, amount: 100) }
    let(:conflict) { create(:sync_conflict, existing_expense: existing_expense, new_expense: nil, status: 'pending') }

    it 'handles custom resolution when new_expense is nil' do
      custom_data = {
        'existing_expense' => { 'amount' => 200 },
        'new_expense' => { 'amount' => 300 }
      }

      expect { conflict.resolve!('custom', custom_data) }.not_to raise_error
      expect(existing_expense.reload.amount).to eq(200)
    end
  end

  describe 'callbacks', integration: true do
    let(:conflict) { create(:sync_conflict, :with_new_expense, status: 'pending') }

    it 'broadcasts resolution when status changes to resolved' do
      expect(SyncStatusChannel).to receive(:broadcast_to).with(
        conflict.sync_session,
        hash_including(event: 'conflict_resolved')
      )

      conflict.update(status: 'resolved')
    end
  end
end
