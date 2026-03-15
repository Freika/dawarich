# frozen_string_literal: true

FactoryBot.define do
  factory :track do
    association :user
    start_at { 1.hour.ago }
    end_at { 30.minutes.ago }
    original_path { 'LINESTRING(-74.0060 40.7128, -74.0070 40.7130)' }
    distance { 1500.0 } # in meters
    avg_speed { 25.0 } # in km/h
    duration { 1800 } # 30 minutes in seconds
    elevation_gain { 50 }
    elevation_loss { 20 }
    elevation_max { 100 }
    elevation_min { 50 }
  end
end
