# frozen_string_literal: true

FactoryBot.define do
  factory :track_segment do
    association :track
    transportation_mode { :driving }
    start_index { 0 }
    end_index { 10 }
    distance { 1000 }
    duration { 600 }
    avg_speed { 30.0 }
    max_speed { 50.0 }
    avg_acceleration { 0.5 }
    confidence { :medium }
    source { 'inferred' }

    trait :walking do
      transportation_mode { :walking }
      avg_speed { 5.0 }
      max_speed { 7.0 }
      avg_acceleration { 0.1 }
    end

    trait :cycling do
      transportation_mode { :cycling }
      avg_speed { 20.0 }
      max_speed { 35.0 }
      avg_acceleration { 0.2 }
    end

    trait :running do
      transportation_mode { :running }
      avg_speed { 12.0 }
      max_speed { 18.0 }
      avg_acceleration { 0.3 }
    end

    trait :train do
      transportation_mode { :train }
      avg_speed { 150.0 }
      max_speed { 200.0 }
      avg_acceleration { 0.1 }
    end

    trait :flying do
      transportation_mode { :flying }
      avg_speed { 800.0 }
      max_speed { 900.0 }
      avg_acceleration { 0.2 }
    end

    trait :stationary do
      transportation_mode { :stationary }
      avg_speed { 0.0 }
      max_speed { 0.5 }
      avg_acceleration { 0.0 }
      distance { 0 }
    end

    trait :from_source do
      source { 'overland' }
      confidence { :high }
    end
  end
end
