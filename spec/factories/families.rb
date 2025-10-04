# frozen_string_literal: true

FactoryBot.define do
  factory :family do
    sequence(:name) { |n| "Test Family #{n}" }
    association :creator, factory: :user
  end
end
