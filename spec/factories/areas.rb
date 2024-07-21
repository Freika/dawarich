# frozen_string_literal: true

FactoryBot.define do
  factory :area do
    name { 'Adlershof' }
    user
    latitude { 52.437 }
    longitude { 13.539 }
    radius { 100 }
  end
end
