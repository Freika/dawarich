# frozen_string_literal: true

FactoryBot.define do
  factory :flight do
    user
    sequence(:external_id) { |n| n }
    flight_date { Date.new(2026, 4, 20) }
    date_precision { 'day' }
    departure_time { Time.utc(2026, 4, 20, 10) }
    arrival_time { Time.utc(2026, 4, 20, 12) }
    from_code { 'EDDB' }
    from_name { 'Berlin Brandenburg' }
    from_lat { 52.351 }
    from_lon { 13.493 }
    to_code { 'LFPG' }
    to_name { 'Paris CDG' }
    to_lat { 49.009 }
    to_lon { 2.547 }
    airline_name { 'Air France' }
    airline_iata { 'AF' }
    flight_number { 'AF1235' }
    distance_km { 878.0 }
  end
end
