# frozen_string_literal: true

FactoryBot.define do
  factory :track do
    started_at { DateTime.new(2025, 1, 23, 15, 59, 55) }
    ended_at { DateTime.new(2025, 1, 23, 16, 0, 0) }
    user
    path { 'LINESTRING(0 0, 1 1, 2 2)' }
  end
end
