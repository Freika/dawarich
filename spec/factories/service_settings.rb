# frozen_string_literal: true

FactoryBot.define do
  factory :service_setting do
    user
    service { :geocoding }
    provider { 'photon' }
    config { { 'host' => 'photon.example.com', 'use_https' => true } }
    active { false }

    trait :active do
      active { true }
    end

    trait :geoapify do
      provider { 'geoapify' }
      config { {} }
      api_key { 'test-api-key' }
    end

    trait :nominatim do
      provider { 'nominatim' }
      config { { 'host' => 'nominatim.example.com', 'use_https' => true } }
    end

    trait :locationiq do
      provider { 'locationiq' }
      config { {} }
      api_key { 'test-api-key' }
    end
  end
end
