# frozen_string_literal: true

FactoryBot.define do
  factory :video_export do
    user
    track { nil }
    start_at { 1.day.ago }
    end_at { Time.current }
    status { :created }
    config do
      {
        'orientation' => 'landscape',
        'speed_multiplier' => 10,
        'map_style' => 'dark',
        'map_behavior' => 'north_up',
        'overlays' => { 'time' => true, 'speed' => true, 'distance' => true, 'track_name' => true }
      }
    end

    trait :with_track do
      track
    end

    trait :processing do
      status { :processing }
      processing_started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      processing_started_at { 5.minutes.ago }
      after(:create) do |video_export|
        video_export.file.attach(
          io: StringIO.new('fake video content'),
          filename: 'route_replay.mp4',
          content_type: 'video/mp4'
        )
      end
    end

    trait :failed do
      status { :failed }
      processing_started_at { 5.minutes.ago }
      error_message { 'Render timeout exceeded' }
    end
  end
end
