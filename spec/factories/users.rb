# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence :email do |n|
      "user#{n}-#{Time.current.to_f}@example.com"
    end

    status { :active }
    active_until { 1000.years.from_now }

    password { SecureRandom.hex(8) }

    settings do
      {
        'route_opacity' => 60,
        'meters_between_routes' => '500',
        'minutes_between_routes' => '30',
        'fog_of_war_meters' => '100',
        'time_threshold_minutes' => '30',
        'merge_threshold_minutes' => '15',
        'maps' => {
          'distance_unit' => 'km'
        }
      }
    end

    trait :admin do
      admin { true }
    end

    trait :inactive do
      status { :inactive }
      active_until { 1.day.ago }
    end

    trait :trial do
      status { :trial }
      active_until { 7.days.from_now }
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
