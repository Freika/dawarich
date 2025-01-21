# frozen_string_literal: true

FactoryBot.define do
  factory :trip do
    user
    name { FFaker::Lorem.word }
    started_at { DateTime.new(2024, 11, 27, 17, 16, 21) }
    ended_at { DateTime.new(2024, 11, 29, 17, 16, 21) }
    notes { FFaker::Lorem.sentence }

    trait :with_points do
      after(:build) do |trip|
        (1..25).map do |i|
          create(
            :point,
            :with_geodata,
            :reverse_geocoded,
            timestamp: trip.started_at + i.minutes,
            user: trip.user
          )
        end
      end
    end
  end
end
