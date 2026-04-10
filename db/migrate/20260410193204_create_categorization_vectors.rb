class CreateCategorizationVectors < ActiveRecord::Migration[8.1]
  def change
    create_table :categorization_vectors do |t|
      t.string :merchant_normalized, null: false
      t.references :category, null: false, foreign_key: true
      t.integer :occurrence_count, default: 1, null: false
      t.integer :correction_count, default: 0, null: false
      t.float :confidence, default: 0.5, null: false
      t.string :description_keywords, array: true, default: []
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :categorization_vectors, :merchant_normalized,
              using: :gist, opclass: :gist_trgm_ops,
              name: "index_categorization_vectors_on_merchant_trgm"
    add_index :categorization_vectors, [ :merchant_normalized, :category_id ],
              unique: true,
              name: "index_categorization_vectors_on_merchant_and_category"
  end
end
