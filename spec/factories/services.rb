FactoryBot.define do
  factory :service do
    name { FFaker::Color.name }
    description { FFaker::Company.catch_phrase }
  end
end
