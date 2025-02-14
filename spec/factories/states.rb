# frozen_string_literal: true

FactoryBot.define do
  factory :state do
    name { FFaker::AddressAU.state }
    country
  end
end
