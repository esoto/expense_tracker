# frozen_string_literal: true

class CreateUndoHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :undo_histories do |t|
      t.references :undoable, polymorphic: true, index: true
      # Optional user reference (no foreign key since users table doesn't exist yet)
      t.bigint :user_id, index: true
      t.integer :action_type, null: false, index: true
      t.jsonb :record_data, null: false, default: {}
      t.string :description
      t.boolean :is_bulk, default: false, index: true
      t.integer :affected_count, default: 1
      t.datetime :expires_at, index: true
      t.datetime :expired_at
      t.datetime :undone_at, index: true

      t.timestamps
    end

    add_index :undo_histories, :created_at
    add_index :undo_histories, [:user_id, :created_at]
    add_index :undo_histories, [:action_type, :undone_at]
    add_index :undo_histories, [:expires_at, :undone_at], where: "undone_at IS NULL"
  end
end
