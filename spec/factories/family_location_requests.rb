# frozen_string_literal: true

FactoryBot.define do
  factory :family_location_request, class: 'Family::LocationRequest' do
    association :requester, factory: :user
    association :target_user, factory: :user
    association :family
    status { :pending }
    expires_at { 24.hours.from_now }
    suggested_duration { '24h' }
  end
end
