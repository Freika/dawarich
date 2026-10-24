# frozen_string_literal: true

FactoryBot.define do
  factory :geofence_event do
    user
    area { association :area, user: }
    event_type { :enter }
    source { :native_app }
    occurred_at { Time.current }
    received_at { Time.current }
    lonlat { 'POINT(13.539 52.437)' }
    accuracy_m { 25 }
    metadata { {} }
  end
end
