# frozen_string_literal: true

FactoryBot.define do
  factory :webhook do
    user
    sequence(:name) { |n| "Webhook #{n}" }
    url { 'https://203.0.113.10/hooks/dawarich' }
    event_types { [0, 1] }
    area_ids { [] }
    active { true }
  end
end
