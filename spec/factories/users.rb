# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence :email do |n|
      "user#{n}@example.com"
    end

    status { :active }

    password { SecureRandom.hex(8) }

    settings do
      {
        route_opacity: '0.5',
        meters_between_routes: '100',
        minutes_between_routes: '100',
        fog_of_war_meters: '100',
        time_threshold_minutes: '100',
        merge_threshold_minutes: '100'
      }
    end

    trait :admin do
      admin { true }
    end

    trait :with_immich_integration do
      settings do
        {
          immich_url: 'https://immich.example.com',
          immich_api_key: '1234567890'
        }
      end
    end

    trait :with_photoprism_integration do
      settings do
        {
          photoprism_url: 'https://photoprism.example.com',
          photoprism_api_key: '1234567890'
        }
      end
    end
  end
end
