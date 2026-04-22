# frozen_string_literal: true

FactoryBot.define do
  factory :geofence_event do
    user
    area
    event_type { :enter }
    source { :native_app }
    occurred_at { Time.current }
    received_at { Time.current }
    lonlat { 'POINT(13.4 52.5)' }
    accuracy_m { 25 }
    device_id { SecureRandom.uuid }
    metadata { {} }
  end
end
