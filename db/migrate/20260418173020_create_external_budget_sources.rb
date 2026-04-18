class CreateExternalBudgetSources < ActiveRecord::Migration[8.1]
  def change
    create_table :external_budget_sources do |t|
      t.references :email_account, null: false, foreign_key: true, index: { unique: true }
      t.string :source_type, null: false, default: "salary_calculator"
      t.string :base_url, null: false
      t.text :api_token   # encrypted via Rails `encrypts`
      t.datetime :last_synced_at
      t.string :last_sync_status
      t.text :last_sync_error
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :external_budget_sources, [ :email_account_id, :active ], name: "idx_ebs_on_account_active"
  end
end
