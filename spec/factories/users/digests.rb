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
        '1' => '50000',
        '2' => '45000',
        '3' => '60000',
        '4' => '55000',
        '5' => '40000',
        '6' => '35000',
        '7' => '30000',
        '8' => '45000',
        '9' => '50000',
        '10' => '40000',
        '11' => '25000',
        '12' => '25000'
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
        'total_distance' => '2500000'
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
      month { 1 }
      # Monthly digests use array format: [[day, distance], ...]
      monthly_distances do
        [
          [1, 5000], [2, 3000], [3, 0], [4, 7000], [5, 2000],
          [6, 0], [7, 8000], [8, 4000], [9, 0], [10, 6000],
          [11, 0], [12, 5000], [13, 3000], [14, 0], [15, 9000],
          [16, 0], [17, 7000], [18, 4000], [19, 0], [20, 6000],
          [21, 0], [22, 5000], [23, 3000], [24, 0], [25, 8000],
          [26, 0], [27, 7000], [28, 4000], [29, 0], [30, 5000],
          [31, 2000]
        ]
      end
    end

    trait :without_previous_year do
      year_over_year { {} }
    end

    trait :first_year do
      first_time_visits do
        {
          'countries' => %w[Germany France Spain],
          'cities' => %w[Berlin Paris Madrid Barcelona]
        }
      end
      year_over_year { {} }
    end
  end
end
