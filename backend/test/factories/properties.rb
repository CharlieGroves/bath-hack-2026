FactoryBot.define do
  factory :property do
    sequence(:rightmove_id) { |n| (100_000_000 + n).to_s }
    address_line_1 { "#{Faker::Address.building_number} #{Faker::Address.street_name}, Bath" }
    town          { "Bath" }
    postcode      { "BA1" }
    price_pence   { 35_000_000 }
    property_type { "terraced" }
    bedrooms      { 3 }
    bathrooms     { 1 }
    status        { "active" }
    key_features  { ["Garden", "Garage"] }
    photo_urls    { ["https://example.com/photo1.jpg"] }
    listed_at     { 1.month.ago }

    trait :under_offer do
      status        { "under_offer" }
      property_type { "flat" }
      price_pence   { 25_000_000 }
      bedrooms      { 2 }
      key_features  { [] }
      photo_urls    { [] }
    end
  end
end
