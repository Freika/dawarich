# frozen_string_literal: true

FactoryBot.define do
  factory :family_membership do
    association :family
    association :user
    role { :member }

    trait :owner do
      role { :owner }
    end
  end
end
