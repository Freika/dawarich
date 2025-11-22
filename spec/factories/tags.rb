# frozen_string_literal: true

FactoryBot.define do
  factory :tag do
    sequence(:name) { |n| "Tag #{n}" }
    icon { %w[📍 🏠 🏢 🍴 ☕ 🏨 🎭 🏛️ 🌳 ⛰️].sample }
    color { "##{SecureRandom.hex(3)}" }
    association :user

    trait :home do
      name { 'Home' }
      icon { '🏠' }
      color { '#4CAF50' }
    end

    trait :work do
      name { 'Work' }
      icon { '🏢' }
      color { '#2196F3' }
    end

    trait :restaurant do
      name { 'Restaurant' }
      icon { '🍴' }
      color { '#FF9800' }
    end

    trait :without_color do
      color { nil }
    end

    trait :without_icon do
      icon { nil }
    end
  end
end
