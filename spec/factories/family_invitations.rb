# frozen_string_literal: true

FactoryBot.define do
  factory :family_invitation, class: 'Family::Invitation' do
    association :family
    association :invited_by, factory: :user
    sequence(:email) { |n| "invite#{n}@example.com" }
    token { SecureRandom.urlsafe_base64(32) }
    expires_at { 7.days.from_now }
    status { :pending }

    trait :accepted do
      status { :accepted }
    end

    trait :expired do
      status { :expired }
      expires_at { 1.day.ago }
    end

    trait :cancelled do
      status { :cancelled }
    end

    trait :with_expired_date do
      expires_at { 1.day.ago }
    end
  end
end
