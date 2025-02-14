# frozen_string_literal: true

FactoryBot.define do
  factory :country do
    name { FFaker::Address.country }
    iso2_code { FFaker::Address.country_code }
  end
end
