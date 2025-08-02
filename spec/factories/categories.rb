FactoryBot.define do
  factory :category do
    sequence(:name) { |n| "Category #{n}" }
    description { "Test category description" }
    color { "#FF6B6B" }
    parent { nil }

    trait :with_parent do
      association :parent, factory: :category
    end

    trait :root do
      parent { nil }
    end

    trait :alimentacion do
      name { "Alimentación" }
      description { "Comida, restaurantes, supermercados" }
      color { "#FF6B6B" }
    end

    trait :transporte do
      name { "Transporte" }
      description { "Gasolina, Uber, taxis, transporte público" }
      color { "#4ECDC4" }
    end

    trait :restaurantes do
      name { "Restaurantes" }
      description { "Comidas en restaurantes" }
      association :parent, factory: [:category, :alimentacion]
    end
  end
end