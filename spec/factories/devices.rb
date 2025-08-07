# frozen_string_literal: true

FactoryBot.define do
  factory :device do
    name { SecureRandom.uuid }
    user
    identifier { SecureRandom.uuid }
  end
end
