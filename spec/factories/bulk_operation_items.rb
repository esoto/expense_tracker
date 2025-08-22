FactoryBot.define do
  factory :bulk_operation_item do
    association :bulk_operation
    association :expense
    association :previous_category, factory: :category
    association :new_category, factory: :category
    status { :pending }
    previous_confidence { 0.75 }
    
    trait :completed do
      status { :completed }
      processed_at { Time.current }
    end
    
    trait :failed do
      status { :failed }
      error_message { "Processing failed" }
    end
  end
end