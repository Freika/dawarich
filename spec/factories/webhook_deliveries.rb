# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_delivery do
    webhook
    geofence_event
    status { :pending }
    attempt_count { 0 }
  end
end
