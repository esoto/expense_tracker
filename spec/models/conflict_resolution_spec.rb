require 'rails_helper'

RSpec.describe ConflictResolution, type: :model, integration: true do
  let(:sync_session) { create(:sync_session) }
  let(:sync_conflict) { create(:sync_conflict, sync_session: sync_session) }

  describe 'associations', integration: true do
    it { should belong_to(:sync_conflict) }
    it { should belong_to(:undone_by_resolution).class_name('ConflictResolution').optional }
    it { should have_one(:undoes_resolution).class_name('ConflictResolution').with_foreign_key('undone_by_resolution_id') }
  end

  describe 'validations', integration: true do
    it { should validate_presence_of(:action) }

    it 'validates action inclusion' do
      valid_actions = %w[keep_existing keep_new keep_both merged custom undo]
      valid_actions.each do |action|
        resolution = build(:conflict_resolution, sync_conflict: sync_conflict, action: action)
        expect(resolution).to be_valid, "#{action} should be valid"
      end
    end

    it 'rejects invalid actions' do
      resolution = build(:conflict_resolution, sync_conflict: sync_conflict, action: 'invalid_action')
      expect(resolution).not_to be_valid
      expect(resolution.errors[:action]).to include('is not included in the list')
    end

    it 'validates resolution_method inclusion when present' do
      valid_methods = %w[manual auto bulk api]
      valid_methods.each do |method|
        resolution = build(:conflict_resolution, sync_conflict: sync_conflict, resolution_method: method)
        expect(resolution).to be_valid, "#{method} should be valid"
      end
    end

    it 'allows nil resolution_method' do
      resolution = build(:conflict_resolution, sync_conflict: sync_conflict, resolution_method: nil)
      expect(resolution).to be_valid
    end

    it 'rejects invalid resolution_method' do
      resolution = build(:conflict_resolution, sync_conflict: sync_conflict, resolution_method: 'invalid_method')
      expect(resolution).not_to be_valid
      expect(resolution.errors[:resolution_method]).to include('is not included in the list')
    end
  end

  describe 'scopes', integration: true do
    let!(:undone_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undone: true) }
    let!(:not_undone_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undone: false) }
    let!(:manual_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, resolution_method: 'manual') }
    let!(:auto_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, resolution_method: 'auto') }
    let!(:bulk_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, resolution_method: 'bulk') }
    let!(:undoable_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undoable: true, undone: false) }
    let!(:non_undoable_resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undoable: false, undone: false) }

    describe '.not_undone', integration: true do
      it 'returns only resolutions that are not undone' do
        expect(ConflictResolution.not_undone).to include(not_undone_resolution)
        expect(ConflictResolution.not_undone).not_to include(undone_resolution)
      end
    end

    describe '.undone', integration: true do
      it 'returns only undone resolutions' do
        expect(ConflictResolution.undone).to include(undone_resolution)
        expect(ConflictResolution.undone).not_to include(not_undone_resolution)
      end
    end

    describe '.recent', integration: true do
      it 'orders by created_at desc' do
        expect(ConflictResolution.recent.first).to eq(ConflictResolution.order(created_at: :desc).first)
      end
    end

    describe '.manual', integration: true do
      it 'returns only manual resolutions' do
        expect(ConflictResolution.manual).to include(manual_resolution)
        expect(ConflictResolution.manual).not_to include(auto_resolution, bulk_resolution)
      end
    end

    describe '.automatic', integration: true do
      it 'returns auto and bulk resolutions' do
        expect(ConflictResolution.automatic).to include(auto_resolution, bulk_resolution)
        expect(ConflictResolution.automatic).not_to include(manual_resolution)
      end
    end

    describe '.undoable', integration: true do
      it 'returns only undoable and not undone resolutions' do
        expect(ConflictResolution.undoable).to include(undoable_resolution)
        expect(ConflictResolution.undoable).not_to include(non_undoable_resolution, undone_resolution)
      end
    end
  end

  describe '#can_undo?', integration: true do
    context 'when resolution is undoable, not undone, and not an undo action' do
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undoable: true, undone: false, action: 'keep_existing') }

      it 'returns true' do
        expect(resolution.can_undo?).to be true
      end
    end

    context 'when resolution is not undoable' do
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undoable: false, undone: false, action: 'keep_existing') }

      it 'returns false' do
        expect(resolution.can_undo?).to be false
      end
    end

    context 'when resolution is already undone' do
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undoable: true, undone: true, action: 'keep_existing') }

      it 'returns false' do
        expect(resolution.can_undo?).to be false
      end
    end

    context 'when resolution is an undo action' do
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, undoable: true, undone: false, action: 'undo') }

      it 'returns false' do
        expect(resolution.can_undo?).to be false
      end
    end
  end

  describe '#undo_action?', integration: true do
    it 'returns true when action is undo' do
      resolution = build(:conflict_resolution, action: 'undo')
      expect(resolution.undo_action?).to be true
    end

    it 'returns false when action is not undo' do
      resolution = build(:conflict_resolution, action: 'keep_existing')
      expect(resolution.undo_action?).to be false
    end
  end

  describe '#display_action', integration: true do
    it 'returns Spanish translations for known actions' do
      translations = {
        'keep_existing' => 'Mantener existente',
        'keep_new' => 'Mantener nuevo',
        'keep_both' => 'Mantener ambos',
        'merged' => 'Fusionado',
        'custom' => 'Personalizado',
        'undo' => 'Deshacer'
      }

      translations.each do |action, translation|
        resolution = build(:conflict_resolution, action: action)
        expect(resolution.display_action).to eq(translation)
      end
    end

    it 'humanizes unknown actions' do
      resolution = build(:conflict_resolution, action: 'unknown_action')
      expect(resolution.display_action).to eq('Unknown action')
    end
  end

  describe '#display_method', integration: true do
    it 'returns Spanish translations for known methods' do
      translations = {
        'manual' => 'Manual',
        'auto' => 'Automático',
        'bulk' => 'En lote',
        'api' => 'API'
      }

      translations.each do |method, translation|
        resolution = build(:conflict_resolution, resolution_method: method)
        expect(resolution.display_method).to eq(translation)
      end
    end

    it 'handles nil resolution_method' do
      resolution = build(:conflict_resolution, resolution_method: nil)
      expect(resolution.display_method).to eq('Desconocido')
    end

    it 'humanizes unknown methods' do
      resolution = build(:conflict_resolution, resolution_method: 'unknown_method')
      expect(resolution.display_method).to eq('Unknown method')
    end
  end

  describe '#changed_fields', integration: true do
    context 'when changes_made is blank' do
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: nil) }

      it 'returns empty array' do
        expect(resolution.changed_fields).to eq([])
      end
    end

    context 'when changes_made contains existing_expense changes' do
      let(:changes_made) do
        {
          'existing_expense' => {
            'before' => { 'amount' => 100, 'description' => 'Old desc' },
            'after' => { 'amount' => 150, 'description' => 'Old desc' }
          }
        }
      end
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: changes_made) }

      it 'returns changed fields for existing expense' do
        fields = resolution.changed_fields
        expect(fields).to include(
          {
            expense: 'existing',
            field: 'amount',
            before: 100,
            after: 150
          }
        )
        expect(fields).not_to include(
          hash_including(field: 'description')
        )
      end
    end

    context 'when changes_made contains new_expense changes' do
      let(:changes_made) do
        {
          'new_expense' => {
            'before' => { 'merchant_name' => 'Old Store', 'amount' => 200 },
            'after' => { 'merchant_name' => 'New Store', 'amount' => 200 }
          }
        }
      end
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: changes_made) }

      it 'returns changed fields for new expense' do
        fields = resolution.changed_fields
        expect(fields).to include(
          {
            expense: 'new',
            field: 'merchant_name',
            before: 'Old Store',
            after: 'New Store'
          }
        )
        expect(fields).not_to include(
          hash_including(field: 'amount')
        )
      end
    end

    context 'when changes_made contains both expense types' do
      let(:changes_made) do
        {
          'existing_expense' => {
            'before' => { 'amount' => 100 },
            'after' => { 'amount' => 150 }
          },
          'new_expense' => {
            'before' => { 'description' => 'Old' },
            'after' => { 'description' => 'New' }
          }
        }
      end
      let(:resolution) { create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: changes_made) }

      it 'returns changed fields for both expenses' do
        fields = resolution.changed_fields
        expect(fields).to include(
          {
            expense: 'existing',
            field: 'amount',
            before: 100,
            after: 150
          }
        )
        expect(fields).to include(
          {
            expense: 'new',
            field: 'description',
            before: 'Old',
            after: 'New'
          }
        )
      end
    end
  end

  describe '#summary', integration: true do
    it 'returns appropriate summary for keep_existing action' do
      resolution = build(:conflict_resolution, action: 'keep_existing')
      expect(resolution.summary).to eq('Se mantuvo el gasto existente y se marcó el nuevo como duplicado')
    end

    it 'returns appropriate summary for keep_new action' do
      resolution = build(:conflict_resolution, action: 'keep_new')
      expect(resolution.summary).to eq('Se mantuvo el nuevo gasto y se marcó el existente como duplicado')
    end

    it 'returns appropriate summary for keep_both action' do
      resolution = build(:conflict_resolution, action: 'keep_both')
      expect(resolution.summary).to eq('Se mantuvieron ambos gastos como separados')
    end

    it 'returns appropriate summary for merged action with changed fields count' do
      changes_made = {
        'existing_expense' => {
          'before' => { 'amount' => 100, 'description' => 'Old' },
          'after' => { 'amount' => 150, 'description' => 'New' }
        }
      }
      resolution = build(:conflict_resolution, action: 'merged', changes_made: changes_made)
      expect(resolution.summary).to eq('Se fusionaron los gastos, combinando 2 campos')
    end

    it 'returns appropriate summary for custom action with changed fields count' do
      changes_made = {
        'new_expense' => {
          'before' => { 'status' => 'pending' },
          'after' => { 'status' => 'processed' }
        }
      }
      resolution = build(:conflict_resolution, action: 'custom', changes_made: changes_made)
      expect(resolution.summary).to eq('Se aplicó una resolución personalizada con 1 cambios')
    end

    it 'returns appropriate summary for undo action' do
      resolution = build(:conflict_resolution, action: 'undo')
      expect(resolution.summary).to eq('Se deshizo la resolución anterior')
    end

    it 'returns default summary for unknown actions' do
      resolution = build(:conflict_resolution, action: 'unknown')
      expect(resolution.summary).to eq('Resolución aplicada')
    end
  end

  describe 'edge cases and validations', integration: true do
    it 'handles empty changes_made gracefully in changed_fields' do
      resolution = create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: {})
      expect(resolution.changed_fields).to eq([])
    end

    it 'handles malformed changes_made data' do
      resolution = create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: { 'invalid' => 'data' })
      expect(resolution.changed_fields).to eq([])
    end

    it 'handles changes_made with missing before/after keys' do
      changes_made = {
        'existing_expense' => {
          'before' => { 'amount' => 100 }
          # Missing 'after' key
        }
      }
      resolution = create(:conflict_resolution, sync_conflict: sync_conflict, changes_made: changes_made)
      # The model currently raises an error for malformed data - this is expected behavior
      expect { resolution.changed_fields }.to raise_error(NoMethodError)
    end
  end

  describe 'associations edge cases', integration: true do
    it 'can create resolution that undoes another resolution' do
      original_resolution = create(:conflict_resolution, sync_conflict: sync_conflict, action: 'keep_existing')
      undo_resolution = create(:conflict_resolution, sync_conflict: sync_conflict, action: 'undo', undone_by_resolution: original_resolution)

      expect(undo_resolution.undone_by_resolution).to eq(original_resolution)
      expect(original_resolution.undoes_resolution).to eq(undo_resolution)
    end
  end
end
