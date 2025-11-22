# frozen_string_literal: true

FactoryBot.define do
  factory :tagging do
    association :taggable, factory: :place
    association :tag
  end
end
