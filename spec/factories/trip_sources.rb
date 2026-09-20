# frozen_string_literal: true

FactoryBot.define do
  factory :trip_source do
    user
    provider { 'trek' }
    base_url { 'https://trek.example.test' }
    api_key { 'trek_test_key' }
  end
end
