class CreateCategorizationPatternTables < ActiveRecord::Migration[8.0]
  def change
    # Enable PostgreSQL extensions for fuzzy matching
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')
    enable_extension 'unaccent' unless extension_enabled?('unaccent')

    # Main categorization patterns table
    create_table :categorization_patterns do |t|
      t.references :category, null: false, foreign_key: true
      t.string :pattern_type, null: false # merchant, keyword, description, amount_range, regex, time
      t.string :pattern_value, null: false
      t.float :confidence_weight, default: 1.0
      t.integer :usage_count, default: 0
      t.integer :success_count, default: 0
      t.float :success_rate, default: 0.0
      t.jsonb :metadata, default: {} # Store additional pattern data
      t.boolean :active, default: true
      t.boolean :user_created, default: false
      t.timestamps

      # Indexes for performance
      t.index [ :pattern_type, :pattern_value ]
      t.index [ :category_id, :success_rate ]
      t.index [ :active, :pattern_type ]
      t.index :pattern_value, using: :gin, opclass: :gin_trgm_ops # For fuzzy matching
    end

    # Canonical merchants table for merchant normalization
    create_table :canonical_merchants do |t|
      t.string :name, null: false # Normalized name
      t.string :display_name
      t.string :category_hint
      t.jsonb :metadata, default: {}
      t.integer :usage_count, default: 0
      t.timestamps

      t.index :name, unique: true
      t.index :usage_count
    end

    # Merchant aliases for handling variations
    create_table :merchant_aliases do |t|
      t.string :raw_name, null: false
      t.string :normalized_name, null: false
      t.references :canonical_merchant, foreign_key: true
      t.float :confidence, default: 1.0
      t.integer :match_count, default: 0
      t.datetime :last_seen_at
      t.timestamps

      t.index :raw_name
      t.index :normalized_name, using: :gin, opclass: :gin_trgm_ops
      t.index [ :canonical_merchant_id, :confidence ]
    end

    # Track pattern learning from user corrections
    create_table :pattern_feedbacks do |t|
      t.references :categorization_pattern, foreign_key: true
      t.references :expense, foreign_key: true
      t.references :category, foreign_key: true # The correct category
      t.boolean :was_correct
      t.float :confidence_score
      t.string :feedback_type # 'correction', 'confirmation', 'rejection'
      t.jsonb :context_data, default: {}
      t.timestamps

      t.index [ :categorization_pattern_id, :was_correct ]
      t.index :created_at
    end

    # User-specific categorization preferences
    create_table :user_category_preferences do |t|
      t.references :email_account, foreign_key: true # Using email_account instead of user
      t.references :category, foreign_key: true
      t.string :context_type # 'merchant', 'time_of_day', 'day_of_week', 'amount_range'
      t.string :context_value
      t.integer :preference_weight, default: 1
      t.integer :usage_count, default: 0
      t.timestamps

      t.index [ :email_account_id, :context_type, :context_value ]
    end

    # Pattern learning events for tracking system performance
    create_table :pattern_learning_events do |t|
      t.references :expense, foreign_key: true
      t.references :category, foreign_key: true
      t.string :pattern_used
      t.boolean :was_correct
      t.float :confidence_score
      t.jsonb :context_data, default: {}
      t.timestamps

      t.index :pattern_used
      t.index :was_correct
      t.index :created_at
    end

    # Add new columns to expenses table for tracking
    add_column :expenses, :merchant_normalized, :string unless column_exists?(:expenses, :merchant_normalized)
    add_column :expenses, :auto_categorized, :boolean, default: false unless column_exists?(:expenses, :auto_categorized)
    add_column :expenses, :categorization_confidence, :float unless column_exists?(:expenses, :categorization_confidence)
    add_column :expenses, :categorization_method, :string unless column_exists?(:expenses, :categorization_method)

    add_index :expenses, :merchant_normalized unless index_exists?(:expenses, :merchant_normalized)
    add_index :expenses, [ :auto_categorized, :categorization_confidence ] unless index_exists?(:expenses, [ :auto_categorized, :categorization_confidence ])
  end
end
