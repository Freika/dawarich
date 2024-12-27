# frozen_string_literal: true

FactoryBot.define do
  factory :state do
    name { FFaker::Address.state }
    country
  end
end
