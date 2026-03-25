# frozen_string_literal: true

FactoryBot.define do
  factory :undo_history do
    action_type { :soft_delete }
    undoable_type { "Expense" }
    record_data { { "id" => 1, "merchant_name" => "Test Merchant", "amount" => 1000 } }
    description { "Deleted expense: Test Merchant" }
    is_bulk { false }
    affected_count { 1 }
    undone_at { nil }
    expired_at { nil }

    trait :bulk do
      action_type { :bulk_delete }
      is_bulk { true }
      affected_count { 3 }
      record_data do
        {
          "ids" => [ 1, 2, 3 ],
          "records" => [
            { "id" => 1, "merchant_name" => "Merchant A" },
            { "id" => 2, "merchant_name" => "Merchant B" },
            { "id" => 3, "merchant_name" => "Merchant C" }
          ]
        }
      end
      description { "Deleted 3 expenses" }
    end

    trait :undone do
      undone_at { Time.current }
    end

    trait :expired do
      expired_at { 1.minute.ago }
      expires_at { 1.minute.ago }
    end
  end
end
