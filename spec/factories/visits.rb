# frozen_string_literal: true

FactoryBot.define do
  factory :visit do
    area
    user
    started_at { Time.zone.now }
    ended_at { Time.zone.now + 1.hour }
    duration { 1.hour }
    name { 'Visit' }
    status { 'suggested' }
  end
end
