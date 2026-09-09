# frozen_string_literal: true

FactoryBot.define do
  factory :route_video do
    user
    name { 'Berlin week' }
    status { :stored }
    settings do
      {
        'theme' => 'noir',
        'format' => 'portrait',
        'duration_sec' => 15,
        'camera_mode' => 'overview',
        'units' => 'km'
      }
    end

    trait :with_file do
      after(:build) do |route_video|
        route_video.file.attach(
          io: Rails.root.join('spec/fixtures/files/route_video.mp4').open,
          filename: 'route_video.mp4',
          content_type: 'video/mp4'
        )
      end
    end

    trait :expired do
      status { :expired }
      expired_at { 1.day.ago }
    end
  end
end
