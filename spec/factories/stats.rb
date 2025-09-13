# frozen_string_literal: true

FactoryBot.define do
  factory :stat do
    year { 1 }
    month { 1 }
    distance { 1000 } # 1 km
    user
    sharing_settings { {} }
    sharing_uuid { SecureRandom.uuid }
    toponyms do
      [
        {
          'cities' => [
            { 'city' => 'Moscow', 'points' => 7, 'timestamp' => 1_554_317_696, 'stayed_for' => 1831 }
          ],
          'country' => 'Russia'
        }, { 'cities' => [], 'country' => nil }
      ]
    end

    trait :with_sharing_enabled do
      after(:create) do |stat, _evaluator|
        stat.enable_sharing!(expiration: 'permanent')
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
  end
end
