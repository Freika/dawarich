# frozen_string_literal: true

FactoryBot.define do
  factory :webhook do
    user
    sequence(:name) { |n| "Webhook #{n}" }
    url { 'https://example.com/hook' }
    event_types { [0, 1] }
    area_ids { [] }
    active { true }
  end
end
