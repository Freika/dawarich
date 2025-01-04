# frozen_string_literal: true

FactoryBot.define do
  factory :county do
    name { FFaker::Address.city }
    country
    state
  end
end
