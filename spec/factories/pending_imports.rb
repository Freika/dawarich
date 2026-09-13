# frozen_string_literal: true

FactoryBot.define do
  factory :pending_import do
    original_filename { 'sample-export.zip' }
    source_hint { 'google_records' }
    origin { 'https://dawarich.app' }
    expires_at { 24.hours.from_now }

    trait :with_file do
      after(:build) do |pending|
        pending.file.attach(
          io: File.open(Rails.root.join('spec/fixtures/files/sample-export.zip')),
          filename: 'sample-export.zip',
          content_type: 'application/zip'
        )
      end
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :claimed do
      claimed_at { 5.minutes.ago }
      claimed_by_user_id { create(:user).id }
    end

    trait :recently_claimed_8_days_ago do
      after(:create) do |pi|
        user = create(:user)
        pi.update!(claimed_at: 8.days.ago, claimed_by_user_id: user.id)
      end
    end
  end
end
