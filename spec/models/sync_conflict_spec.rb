require 'rails_helper'

RSpec.describe SyncConflict, type: :model do
  let(:sync_session) { create(:sync_session) }
  let(:email_account) { create(:email_account) }
  let(:existing_expense) { create(:expense, email_account: email_account, amount: 100, transaction_date: Date.today) }
  let(:new_expense) { create(:expense, email_account: email_account, amount: 100, transaction_date: Date.today, status: 'duplicate') }
  
  describe 'associations' do
    it { should belong_to(:existing_expense).class_name('Expense') }
    it { should belong_to(:new_expense).class_name('Expense').optional }
    it { should belong_to(:sync_session) }
    it { should have_many(:conflict_resolutions).dependent(:destroy) }
  end
  
  describe 'validations' do
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
  
  describe 'scopes' do
    let!(:pending_conflict) { create(:sync_conflict, status: 'pending') }
    let!(:resolved_conflict) { create(:sync_conflict, status: 'resolved') }
    let!(:auto_resolved_conflict) { create(:sync_conflict, status: 'auto_resolved') }
    
    describe '.unresolved' do
      it 'returns only pending conflicts' do
        expect(SyncConflict.unresolved).to include(pending_conflict)
        expect(SyncConflict.unresolved).not_to include(resolved_conflict, auto_resolved_conflict)
      end
    end
    
    describe '.resolved' do
      it 'returns resolved and auto_resolved conflicts' do
        expect(SyncConflict.resolved).to include(resolved_conflict, auto_resolved_conflict)
        expect(SyncConflict.resolved).not_to include(pending_conflict)
      end
    end
  end
  
  describe '#resolve!' do
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
  
  describe '#undo_last_resolution!' do
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
  
  describe '#calculate_similarity_score' do
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
  
  describe '#field_differences' do
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
  
  describe 'callbacks' do
    let(:conflict) { create(:sync_conflict, :with_new_expense, status: 'pending') }
    
    it 'broadcasts resolution when status changes to resolved' do
      expect(SyncChannel).to receive(:broadcast_to).with(
        conflict.sync_session,
        hash_including(event: 'conflict_resolved')
      )
      
      conflict.update(status: 'resolved')
    end
  end
end