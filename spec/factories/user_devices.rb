# frozen_string_literal: true

FactoryBot.define do
  factory :user_device do
    user
    platform { :ios }
    sequence(:device_id) { |n| "device-#{n}" }
    device_name { "iPhone" }
    app_version { "1.0.0" }
    last_seen_at { Time.current }
  end
end
