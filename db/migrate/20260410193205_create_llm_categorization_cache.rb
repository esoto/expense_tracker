class CreateLlmCategorizationCache < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_categorization_cache do |t|
      t.string :merchant_normalized, null: false
      t.references :category, null: false, foreign_key: true
      t.float :confidence
      t.string :model_used, default: "claude-haiku-4-5"
      t.integer :token_count
      t.decimal :cost, precision: 10, scale: 6
      t.datetime :expires_at

      t.timestamps
    end

    add_index :llm_categorization_cache, :merchant_normalized,
              unique: true,
              name: "index_llm_cache_on_merchant_normalized"
    add_index :llm_categorization_cache, :expires_at,
              name: "index_llm_cache_on_expires_at"
  end
end
