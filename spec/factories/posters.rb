# frozen_string_literal: true

FactoryBot.define do
  factory :poster do
    user
    name { 'Berlin' }
    status { :created }
    settings do
      {
        'lat' => 52.52,
        'lon' => 13.405,
        'distance' => 6000,
        'theme' => 'terracotta',
        'start_at' => '2026-04-01T00:00:00Z',
        'end_at' => '2026-04-30T23:59:59Z'
      }
    end
  end
end
