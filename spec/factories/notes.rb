# frozen_string_literal: true

FactoryBot.define do
  factory :note do
    user
    noted_at { Time.current }
    body { FFaker::Lorem.sentence }

    trait :standalone do
      title { FFaker::Lorem.phrase }
      latitude { FFaker::Geolocation.lat }
      longitude { FFaker::Geolocation.lng }
    end

    trait :trip_day do
      attachable { association(:trip, user: user) }
      noted_at { attachable.started_at.to_date.to_datetime.noon }
    end
  end
end
