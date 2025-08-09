FactoryBot.define do
  factory :sync_conflict do
    association :sync_session
    association :existing_expense, factory: :expense
    conflict_type { 'duplicate' }
    status { 'pending' }
    similarity_score { 95.0 }
    priority { 1 }
    conflict_data do
      {
        amount: existing_expense.amount,
        transaction_date: existing_expense.transaction_date,
        merchant_name: existing_expense.merchant_name,
        description: existing_expense.description,
        category_id: existing_expense.category_id
      }
    end
    differences { {} }
    bulk_resolvable { true }
    
    trait :resolved do
      status { 'resolved' }
      resolution_action { 'keep_existing' }
      resolved_at { Time.current }
      resolved_by { 'test_user' }
    end
    
    trait :auto_resolved do
      status { 'auto_resolved' }
      resolution_action { 'keep_existing' }
      resolved_at { Time.current }
      resolved_by { 'system' }
    end
    
    trait :similar do
      conflict_type { 'similar' }
      similarity_score { 75.0 }
    end
    
    trait :needs_review do
      conflict_type { 'needs_review' }
      similarity_score { 50.0 }
      priority { 5 }
    end
    
    trait :with_new_expense do
      association :new_expense, factory: :expense
    end
  end
end