# frozen_string_literal: true

FactoryBot.define do
  factory :shared_link do
    user
    resource_type { :trip }
    sequence(:name) { |n| "Shared link #{n}" }
    settings { { 'show_photos' => false, 'show_stats' => true } }

    transient do
      trip { nil }
      autobuild_trip { true }
    end

    after(:build) do |link, evaluator|
      next unless evaluator.autobuild_trip
      next unless link.resource_type == 'trip'
      next if link.resource_id.present?
      next if link.user.nil?

      link.resource_id = (evaluator.trip || create(:trip, user: link.user)).id
    end

    trait :live do
      resource_type { :live }
      resource_id { nil }
      settings { { 'show_photos' => false } }
    end

    trait :with_phrase do
      magic_phrase { 'blau-tiger-berg' }
    end

    trait :expired do
      after(:create) { |link| link.update_column(:expires_at, 1.minute.ago) }
    end

    trait :revoked do
      revoked_at { 1.minute.ago }
    end
  end
end
