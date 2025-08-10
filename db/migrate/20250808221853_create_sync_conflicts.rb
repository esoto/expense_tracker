class CreateSyncConflicts < ActiveRecord::Migration[8.0]
  def change
    create_table :sync_conflicts do |t|
      t.references :existing_expense, null: false, foreign_key: { to_table: :expenses }
      t.references :new_expense, null: true, foreign_key: { to_table: :expenses }
      t.references :sync_session, null: false, foreign_key: true

      # Conflict details
      t.string :conflict_type, null: false # duplicate, similar, updated, needs_review
      t.decimal :similarity_score, precision: 5, scale: 2 # 0.00 to 100.00
      t.jsonb :conflict_data, default: {} # Store detailed comparison data
      t.jsonb :differences, default: {} # Store field-by-field differences

      # Resolution tracking
      t.string :status, null: false, default: 'pending' # pending, resolved, ignored, auto_resolved
      t.string :resolution_action # keep_existing, keep_new, keep_both, merged, custom
      t.jsonb :resolution_data, default: {} # Store merged or custom resolution data
      t.datetime :resolved_at
      t.string :resolved_by # For future user tracking

      # Metadata
      t.text :notes
      t.integer :priority, default: 0 # Higher number = higher priority
      t.boolean :bulk_resolvable, default: true

      t.timestamps
    end

    add_index :sync_conflicts, :status
    add_index :sync_conflicts, :conflict_type
    add_index :sync_conflicts, [ :status, :conflict_type ]
    add_index :sync_conflicts, [ :sync_session_id, :status ]
    add_index :sync_conflicts, :priority
    add_index :sync_conflicts, :resolved_at
    add_index :sync_conflicts, :similarity_score
    add_index :sync_conflicts, :conflict_data, using: :gin
    add_index :sync_conflicts, :differences, using: :gin
  end
end
