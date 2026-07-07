require 'rails_helper'

RSpec.describe Services::ConflictDetectionService, integration: true do
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

      it 'silently skips obvious duplicates (>=90% similarity)' do
        result = service.detect_conflict_for_expense(new_expense_data)
        expect(result).to be_duplicate_skipped
      end

      it 'does not create a conflict record for obvious duplicates' do
        expect {
          service.detect_conflict_for_expense(new_expense_data)
        }.not_to change(SyncConflict, :count)
      end

      it 'still soft-deletes and saves the incoming duplicate expense (audit trail)' do
        # Expense has a default_scope excluding deleted_at rows (SoftDelete concern),
        # so assert against .unscoped rather than the plain .count.
        expect {
          service.detect_conflict_for_expense(new_expense_data)
        }.to change { Expense.unscoped.count }.by(1)

        duplicate = Expense.unscoped.order(:created_at).last
        expect(duplicate.status).to eq('duplicate')
        expect(duplicate.deleted_at).to be_present
      end

      it 'logs the skip at info level with both expense ids and the score' do
        allow(Rails.logger).to receive(:info).and_call_original
        result = service.detect_conflict_for_expense(new_expense_data)

        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/Silently skipped duplicate.*existing=##{existing_expense.id}.*new=##{result.duplicate_expense.id}/)
        )
      end
    end

    context 'when similar expense exists (70-89% similarity)' do
      before do
        existing_expense.update(amount: 95.00) # Slightly different amount
      end

      it 'creates a similar conflict for human review' do
        result = service.detect_conflict_for_expense(new_expense_data)

        expect(result).to be_conflict
        expect(result.conflict).to be_present
        expect(result.conflict.conflict_type).to eq('similar')
        expect(result.conflict.similarity_score).to be_between(70, 90)
      end
    end

    context 'when conflict_type is duplicate' do
      before { existing_expense }

      it 'skips creating conflict for obvious duplicates' do
        result = service.detect_conflict_for_expense(new_expense_data)
        expect(result).to be_duplicate_skipped
        expect(result.conflict).to be_nil
      end
    end

    context 'when the incoming duplicate is an already-persisted expense (batch path sends :id)' do
      before { existing_expense }

      it 'marks the persisted row duplicate instead of inserting an audit copy' do
        # Case-variant merchant_name: dodges the exact-string unique index
        # (as real bank emails do) while normalizing/scoring identically.
        persisted_dup = create(:expense, email_account: existing_expense.email_account,
                                         user: existing_expense.user,
                                         amount: existing_expense.amount,
                                         transaction_date: existing_expense.transaction_date,
                                         merchant_name: existing_expense.merchant_name.upcase,
                                         merchant_normalized: existing_expense.merchant_normalized,
                                         description: existing_expense.description,
                                         status: 'processed')
        data = persisted_dup.attributes.symbolize_keys

        expect {
          result = service.detect_conflict_for_expense(data)
          expect(result).to be_duplicate_skipped
          expect(result.duplicate_expense.id).to eq(persisted_dup.id)
        }.not_to change { Expense.unscoped.count }

        persisted_dup.reload
        expect(persisted_dup.status).to eq('duplicate')
        expect(persisted_dup.deleted_at).to be_present
        expect(SyncConflict.count).to eq(0)
      end
    end

    context 'when a persisted expense scores in the similar band (batch path sends :id)' do
      before { existing_expense.update(amount: 95.00) }

      it 'creates the conflict referencing the persisted row without inserting a copy' do
        persisted_similar = create(:expense, email_account: existing_expense.email_account,
                                             user: existing_expense.user,
                                             amount: 100.00,
                                             transaction_date: existing_expense.transaction_date,
                                             merchant_name: existing_expense.merchant_name.upcase,
                                             merchant_normalized: existing_expense.merchant_normalized,
                                             description: existing_expense.description,
                                             status: 'processed')
        data = persisted_similar.attributes.symbolize_keys

        result = nil
        expect {
          result = service.detect_conflict_for_expense(data)
        }.not_to change { Expense.unscoped.count }

        expect(result).to be_conflict
        expect(result.conflict.conflict_type).to eq('similar')
        expect(result.conflict.new_expense_id).to eq(persisted_similar.id)
        expect(persisted_similar.reload.status).to eq('processed') # live row untouched pending resolution
      end
    end

    context 'when conflict_type is similar' do
      before do
        existing_expense.update(amount: 95.00)
      end

      it 'saves the new expense with deleted_at set' do
        result = service.detect_conflict_for_expense(new_expense_data)

        expect(result).to be_conflict
        expect(result.conflict.conflict_type).to eq('similar')
        expect(result.conflict.new_expense.deleted_at).to be_present
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

      it 'returns a no_conflict result' do
        result = service.detect_conflict_for_expense(new_expense_data)
        expect(result).to be_no_conflict
        expect(result.conflict).to be_nil
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
        result = service.detect_conflict_for_expense(new_expense_data)
        expect(result.existing_expense).to eq(exact_match)
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

      it 'returns only persisted SyncConflict records (obvious duplicates are skipped)' do
        conflicts = service.detect_conflicts_batch(new_expenses_data)

        expect(conflicts).to be_an(Array)
        # Obvious duplicates (>=90% similarity) are silently skipped and never
        # produce a SyncConflict, so they never show up in this array either.
        expect(conflicts.compact).to be_empty
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

    context 'with a legacy conflict scored in the 90-94% band' do
      let!(:existing_expense_for_boundary) { create(:expense, email_account: email_account) }
      let!(:new_expense_for_boundary) { create(:expense, email_account: email_account, status: :pending) }

      let!(:boundary_conflict) do
        conflict = create(:sync_conflict,
          sync_session: sync_session,
          existing_expense: existing_expense_for_boundary,
          new_expense: new_expense_for_boundary,
          similarity_score: 92.0,
          conflict_type: 'duplicate',
          status: 'pending'
        )
        conflict.update_column(:similarity_score, 92.0)
        conflict
      end

      it 'also resolves it (threshold now matches DUPLICATE_THRESHOLD, not the old 95% cutoff)' do
        resolved_count = service.auto_resolve_obvious_duplicates

        expect(boundary_conflict.reload.status).to eq('resolved')
        expect(resolved_count).to eq(2) # high_confidence_conflict + boundary_conflict
      end
    end
  end

  describe '#calculate_similarity with zero-amount expense', :unit do
    let(:zero_amount_expense) do
      build(:expense,
        amount: 0.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase',
        currency: 'crc'
      )
    end

    it 'does not raise ZeroDivisionError when existing expense amount is zero' do
      expense_data = {
        amount: 0.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase',
        currency: 'crc'
      }

      expect {
        service.send(:calculate_similarity, zero_amount_expense, expense_data)
      }.not_to raise_error
    end

    it 'treats zero-amount expenses with zero new amount as exact match (ratio 0)' do
      expense_data = {
        amount: 0.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase',
        currency: 'crc'
      }

      score = service.send(:calculate_similarity, zero_amount_expense, expense_data)
      expect(score).to be >= 95
    end

    it 'returns a numeric score (not an error) when existing amount is zero and new amount is non-zero' do
      expense_data = {
        amount: 50.00,
        transaction_date: Date.today,
        merchant_name: 'Test Store',
        description: 'Purchase',
        currency: 'crc'
      }

      result = nil
      expect {
        result = service.send(:calculate_similarity, zero_amount_expense, expense_data)
      }.not_to raise_error

      expect(result).to be_a(Numeric)
      # When existing.amount == 0 and new.amount != 0, amount_ratio is Float::INFINITY
      # so amount_score == 0 (contributes 0 of 35 points). The score is well below 90.
      expect(result).to be < 90
    end
  end

  describe '#create_conflict transaction safety', :unit do
    # Use `let!` (or an explicit `before`) to ensure existing_expense is persisted
    # before the `change(Expense, :count)` matcher takes its baseline snapshot.
    # Using plain `let` would cause the record to be created lazily inside the
    # `expect { ... }` block, falsely inflating the count delta.
    let!(:existing_expense) { create(:expense, email_account: email_account, status: :processed) }

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

    it 'rolls back the expense when sync_conflicts.create! raises' do
      # Simulate sync_conflicts.create! raising after the expense is saved.
      # Stub SyncConflict#save! to raise so the AR association create! bubbles an error
      # without needing to intercept the collection proxy (which changes each call).
      allow_any_instance_of(SyncConflict).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(SyncConflict.new)
      )

      # Use a non-duplicate type so it doesn't hit the early-return guard
      expect {
        service.send(
          :create_conflict,
          existing_expense: existing_expense,
          new_expense_data: new_expense_data,
          conflict_type: 'needs_review',
          similarity_score: 50.0,
          differences: {}
        )
      }.not_to change(Expense, :count)
    end

    it 'skips creating a SyncConflict for obvious duplicates (>=95% similarity) but still saves the soft-deleted duplicate' do
      result = nil
      # Expense has a default_scope excluding deleted_at rows (SoftDelete concern),
      # so assert against .unscoped rather than the plain .count.
      expect {
        result = service.send(
          :create_conflict,
          existing_expense: existing_expense,
          new_expense_data: new_expense_data,
          conflict_type: 'duplicate',
          similarity_score: 95.0,
          differences: {}
        )
      }.to change { Expense.unscoped.count }.by(1)
      expect(SyncConflict.count).to eq(0)

      expect(result).to be_duplicate_skipped
      expect(result.duplicate_expense.deleted_at).to be_present
      expect(result.duplicate_expense.status).to eq('duplicate')
    end

    it 'skips creating a SyncConflict for duplicates right at the 90% boundary' do
      result = service.send(
        :create_conflict,
        existing_expense: existing_expense,
        new_expense_data: new_expense_data,
        conflict_type: 'duplicate',
        similarity_score: 90.0,
        differences: {}
      )

      expect(result).to be_duplicate_skipped
      expect(SyncConflict.count).to eq(0)
    end

    it 'still creates a SyncConflict for the 70-89% "similar" band' do
      result = nil
      expect {
        result = service.send(
          :create_conflict,
          existing_expense: existing_expense,
          new_expense_data: new_expense_data,
          conflict_type: 'similar',
          similarity_score: 85.0,
          differences: {}
        )
      }.to change(SyncConflict, :count).by(1)

      expect(result).to be_conflict
      expect(result.conflict.conflict_type).to eq('similar')
    end

    it 'returns a no_conflict result and adds an error when the transaction fails' do
      allow_any_instance_of(SyncConflict).to receive(:save!).and_raise(
        ActiveRecord::RecordInvalid.new(SyncConflict.new)
      )

      # Use a non-duplicate type so it doesn't get skipped
      result = service.send(
        :create_conflict,
        existing_expense: existing_expense,
        new_expense_data: new_expense_data,
        conflict_type: 'needs_review',
        similarity_score: 50.0,
        differences: {}
      )

      expect(result).to be_no_conflict
      expect(service.errors).not_to be_empty
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

      it 'returns 0 for nil strings' do
        score = service.send(:string_similarity, nil, 'test')
        expect(score).to eq(0.0)
      end

      it 'calculates partial similarity' do
        score = service.send(:string_similarity, 'test', 'text')
        expect(score).to be_between(25, 90)
      end
    end

    context '#find_candidate_expenses' do
      it 'excludes the source expense from candidates when :id is provided' do
        expense = create(:expense,
          email_account: email_account,
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'Self Store',
          status: 'processed'
        )

        candidates = service.send(:find_candidate_expenses, {
          id: expense.id,
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'Self Store',
          email_account_id: email_account.id
        })

        expect(candidates.map(&:id)).not_to include(expense.id)
      end

      it 'does not filter by id when :id is absent' do
        expense = create(:expense,
          email_account: email_account,
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'No-Id Store',
          status: 'processed'
        )

        candidates = service.send(:find_candidate_expenses, {
          amount: 100.00,
          transaction_date: Date.today,
          merchant_name: 'No-Id Store',
          email_account_id: email_account.id
        })

        expect(candidates.map(&:id)).to include(expense.id)
      end
    end
  end
end
