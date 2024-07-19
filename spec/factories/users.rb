# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence :email do |n|
      "user#{n}@example.com"
    end

    password { SecureRandom.hex(8) }

    trait :admin do
      admin { true }
    end
  end
end
