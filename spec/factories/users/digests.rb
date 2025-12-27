# frozen_string_literal: true

FactoryBot.define do
  factory :users_digest, class: 'Users::Digest' do
    year { 2024 }
    period_type { :yearly }
    distance { 500_000 } # 500 km
    user
    sharing_settings { {} }
    sharing_uuid { SecureRandom.uuid }

    toponyms do
      [
        {
          'country' => 'Germany',
          'cities' => [{ 'city' => 'Berlin' }, { 'city' => 'Munich' }]
        },
        {
          'country' => 'France',
          'cities' => [{ 'city' => 'Paris' }]
        },
        {
          'country' => 'Spain',
          'cities' => [{ 'city' => 'Madrid' }, { 'city' => 'Barcelona' }]
        }
      ]
    end

    monthly_distances do
      {
        '1' => 50_000,
        '2' => 45_000,
        '3' => 60_000,
        '4' => 55_000,
        '5' => 40_000,
        '6' => 35_000,
        '7' => 30_000,
        '8' => 45_000,
        '9' => 50_000,
        '10' => 40_000,
        '11' => 25_000,
        '12' => 25_000
      }
    end

    time_spent_by_location do
      {
        'countries' => [
          { 'name' => 'Germany', 'minutes' => 10_080 },
          { 'name' => 'France', 'minutes' => 4_320 },
          { 'name' => 'Spain', 'minutes' => 2_880 }
        ],
        'cities' => [
          { 'name' => 'Berlin', 'minutes' => 5_040 },
          { 'name' => 'Paris', 'minutes' => 4_320 },
          { 'name' => 'Madrid', 'minutes' => 1_440 }
        ]
      }
    end

    first_time_visits do
      {
        'countries' => ['Spain'],
        'cities' => %w[Madrid Barcelona]
      }
    end

    year_over_year do
      {
        'previous_year' => 2023,
        'distance_change_percent' => 15,
        'countries_change' => 1,
        'cities_change' => 2
      }
    end

    all_time_stats do
      {
        'total_countries' => 10,
        'total_cities' => 45,
        'total_distance' => 2_500_000
      }
    end

    trait :with_sharing_enabled do
      after(:create) do |digest, _evaluator|
        digest.enable_sharing!(expiration: '24h')
      end
    end

    trait :with_sharing_disabled do
      sharing_settings do
        {
          'enabled' => false,
          'expiration' => nil,
          'expires_at' => nil
        }
      end
    end

    trait :with_sharing_expired do
      sharing_settings do
        {
          'enabled' => true,
          'expiration' => '1h',
          'expires_at' => 1.hour.ago.iso8601
        }
      end
    end

    trait :sent do
      sent_at { 1.day.ago }
    end

    trait :monthly do
      period_type { :monthly }
    end

    trait :without_previous_year do
      year_over_year { {} }
    end

    trait :first_year do
      first_time_visits do
        {
          'countries' => %w[Germany France Spain],
          'cities' => ['Berlin', 'Paris', 'Madrid', 'Barcelona']
        }
      end
      year_over_year { {} }
    end
  end
end
