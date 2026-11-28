# frozen_string_literal: true

FactoryBot.define do
  factory :home do
    user
    place { association :place, user: }
  end
end
