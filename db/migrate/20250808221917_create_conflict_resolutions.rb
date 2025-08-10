class CreateConflictResolutions < ActiveRecord::Migration[8.0]
  def change
    create_table :conflict_resolutions do |t|
      t.references :sync_conflict, null: false, foreign_key: true

      # Resolution details
      t.string :action, null: false # keep_existing, keep_new, keep_both, merged, custom, undo
      t.jsonb :before_state, default: {} # State before resolution
      t.jsonb :after_state, default: {} # State after resolution
      t.jsonb :changes_made, default: {} # Track what was changed

      # Undo support
      t.boolean :undoable, default: true
      t.boolean :undone, default: false
      t.datetime :undone_at
      t.references :undone_by_resolution, foreign_key: { to_table: :conflict_resolutions }

      # Metadata
      t.string :resolved_by # For future user tracking
      t.string :resolution_method # manual, auto, bulk, api
      t.text :notes

      t.timestamps
    end

    add_index :conflict_resolutions, :action
    add_index :conflict_resolutions, :undone
    add_index :conflict_resolutions, :created_at
    add_index :conflict_resolutions, [ :sync_conflict_id, :undone ]
    add_index :conflict_resolutions, :before_state, using: :gin
    add_index :conflict_resolutions, :after_state, using: :gin
  end
end
