FactoryBot.define do
  factory :bulk_operation do
    operation_type { :categorization }
    user_id { "user_123" }
    association :target_category, factory: :category
    expense_count { 1 }  # Must be greater than 0 for validation
    total_amount { 100.0 }
    status { :pending }
    metadata { {} }

    trait :completed do
      status { :completed }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      error_message { "Something went wrong" }
    end

    trait :with_items do
      after(:create) do |bulk_operation|
        create_list(:bulk_operation_item, 3, bulk_operation: bulk_operation)
      end
    end
  end
end
