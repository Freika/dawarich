# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Achievements::CollectionSchedule do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:dataset) { Exploration::Dataset.create!(version: "schedule-#{SecureRandom.hex(4)}", completed_at: Time.current) }
  let(:state) { Achievements::CollectionState.create_or_find_by!(user_id: user.id) }

  before do
    allow(Exploration::Geography).to receive(:current).and_return(dataset)
    state.update!(revision: 5, published_revision: 4, completed_at: Time.current,
                  published_dataset_id: dataset.id, timezone_version: Achievements::LocationTimezone.version,
                  privacy_fingerprint: Achievements::PrivacyFingerprint.call(user))
    clear_enqueued_jobs
  end

  it 'waits for the refresh interval before recalculating new points' do
    expect { described_class.call(user) }.not_to have_enqueued_job(Achievements::CollectionCheckJob)

    travel(Exploration::State::REFRESH_INTERVAL + 1.minute) do
      expect { described_class.call(user) }.to have_enqueued_job(Achievements::CollectionCheckJob)
    end
  end

  it 'retries a failed calculation without waiting for the refresh interval' do
    state.update!(failed_at: Time.current)

    expect { described_class.call(user) }.to have_enqueued_job(Achievements::CollectionCheckJob)
  end

  it 'recalculates immediately when the owner changes a selection' do
    expect { described_class.call(user, throttle: false) }.to have_enqueued_job(Achievements::CollectionCheckJob)
  end

  it 'recalculates immediately when privacy zones change' do
    place = create(:place, user: user)
    place.tags << create(:tag, user: user, privacy_radius_meters: 500)

    expect { described_class.call(user) }.to have_enqueued_job(Achievements::CollectionCheckJob)
  end
end
