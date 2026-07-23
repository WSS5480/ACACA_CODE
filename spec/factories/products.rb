FactoryBot.define do
  factory :product do
    sequence(:title) { |n| "Producto de prueba #{n}" }
    sequence(:asin)  { |n| "ASIN#{n.to_s.rjust(6, '0')}" }
    price { 300.0 }
    turns { 3.5 }
    decimal_factor { 0.75 }
    status { 'active' }

    trait :discounted do
      price { 900.0 }
      price_with_discount { 750.0 }
    end
  end
end
