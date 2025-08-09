FactoryBot.define do
  factory :conflict_resolution do
    association :sync_conflict
    resolution_action { 'keep_existing' }
    resolved_by { 'test_user' }
    state_before { {} }
    state_after { {} }
    notes { 'Test resolution' }
    can_undo { true }
    undone { false }
    
    trait :undone do
      undone { true }
      undone_at { Time.current }
      undone_by { 'test_user' }
    end
    
    trait :keep_new do
      resolution_action { 'keep_new' }
    end
    
    trait :keep_both do
      resolution_action { 'keep_both' }
    end
    
    trait :merged do
      resolution_action { 'merged' }
      merged_fields { { amount: 'new', description: 'existing' } }
    end
  end
end