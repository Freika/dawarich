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
        create_list(
          :point, 25,
          user: trip.user,
          timestamp: trip.started_at + (1..1000).to_a.sample.minutes
        )
      end
    end
  end
end
