# frozen_string_literal: true

FactoryBot.define do
  factory :export do
    name { 'export' }
    url { 'exports/export.json' }
    status { 1 }
    user
  end
end
