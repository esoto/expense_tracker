class AddEventTypeToPatternLearningEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :pattern_learning_events, :event_type, :string
    add_column :pattern_learning_events, :metadata, :jsonb, default: {}

    # Add index for event_type for better query performance
    add_index :pattern_learning_events, :event_type
    add_index :pattern_learning_events, [ :event_type, :created_at ]
  end
end
