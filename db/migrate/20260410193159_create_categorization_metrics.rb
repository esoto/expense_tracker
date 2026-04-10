class CreateCategorizationMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :categorization_metrics do |t|
      t.references :expense, null: false, foreign_key: true
      t.string :layer_used, null: false
      t.float :confidence
      t.references :category, foreign_key: true
      t.boolean :was_corrected, default: false, null: false
      t.references :corrected_to_category, foreign_key: { to_table: :categories }
      t.integer :time_to_correction_hours
      t.float :processing_time_ms
      t.decimal :api_cost, precision: 10, scale: 6, default: 0

      t.timestamps
    end

    add_index :categorization_metrics, :layer_used
    add_index :categorization_metrics, :was_corrected
    add_index :categorization_metrics, :created_at
  end
end
