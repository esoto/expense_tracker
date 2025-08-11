FactoryBot.define do
  factory :conflict_resolution do
    association :sync_conflict
    action { 'keep_existing' }
    resolved_by { 'test_user' }
    before_state { {} }
    after_state { {} }
    changes_made { {} }
    notes { 'Test resolution' }
    undoable { true }
    undone { false }
    resolution_method { 'manual' }

    trait :undone do
      undone { true }
      undone_at { Time.current }
    end

    trait :keep_new do
      action { 'keep_new' }
    end

    trait :keep_both do
      action { 'keep_both' }
    end

    trait :merged do
      action { 'merged' }
      changes_made do
        {
          'existing_expense' => {
            'before' => { 'amount' => 100 },
            'after' => { 'amount' => 150 }
          }
        }
      end
    end

    trait :custom do
      action { 'custom' }
    end

    trait :undo do
      action { 'undo' }
    end

    trait :auto_resolution do
      resolution_method { 'auto' }
    end

    trait :bulk_resolution do
      resolution_method { 'bulk' }
    end

    trait :api_resolution do
      resolution_method { 'api' }
    end
  end
end
