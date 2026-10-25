# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::ReattachUntrackedPointsJob, type: :job do
  let(:user_with_orphans) { create(:user) }
  let(:fully_tracked_user) { create(:user) }

  before do
    [user_with_orphans, fully_tracked_user].each do |user|
      Sidekiq.redis { |redis| redis.del(Tracks::ThrottledBackfillJob.redis_key(user.id)) }
    end

    track = create(:track, user: fully_tracked_user)
    create(:point, user: fully_tracked_user, track: track)
    create(:point, user: user_with_orphans, track_id: nil, anomaly: false)
    create(:point, user: create(:user), track_id: nil, anomaly: true)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  it 'schedules a throttled backfill only for users with untracked points' do
    described_class.perform_now

    expect(Tracks::ThrottledBackfillJob).to have_been_enqueued.with(user_with_orphans.id, nil).exactly(:once)
    expect(enqueued_jobs.count { |job| job['job_class'] == 'Tracks::ThrottledBackfillJob' }).to eq(1)
  end

  it 'does not schedule a second walk for a user whose backfill is already running' do
    Tracks::ThrottledBackfillJob.schedule(user_with_orphans)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.perform_now

    expect(Tracks::ThrottledBackfillJob).not_to have_been_enqueued
  end
end
