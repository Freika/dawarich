# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_delivery do
    webhook
    geofence_event { association :geofence_event, user: webhook.user }
    status { :pending }
    attempt_count { 0 }
  end
end
