# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::ReattachUntrackedPointsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user_with_orphans) { create(:user) }
  let(:fully_tracked_user) { create(:user) }
  let(:user_with_old_orphans) { create(:user) }
  let(:user_without_tracks) { create(:user) }
  let(:inactive_user) { create(:user).tap { |user| user.update_column(:status, :inactive) } }

  before do
    [user_with_orphans, fully_tracked_user, user_with_old_orphans, user_without_tracks, inactive_user].each do |user|
      Sidekiq.redis { |redis| redis.del(Tracks::ThrottledBackfillJob.redis_key(user.id)) }
    end

    track = create(:track, user: fully_tracked_user)
    create(:point, user: fully_tracked_user, track: track, timestamp: 1.day.ago.to_i)
    [user_with_orphans, user_with_old_orphans, inactive_user].each { |user| create(:track, user: user) }
    create(:point, user: user_with_orphans, track_id: nil, anomaly: false, timestamp: 1.day.ago.to_i)
    create(:point, user: user_with_old_orphans, track_id: nil, anomaly: false, timestamp: 2.years.ago.to_i)
    create(:point, user: user_without_tracks, track_id: nil, anomaly: false, timestamp: 1.day.ago.to_i)
    create(:point, user: inactive_user, track_id: nil, anomaly: false, timestamp: 1.day.ago.to_i)
    anomaly_only_user = create(:user)
    create(:track, user: anomaly_only_user)
    create(:point, user: anomaly_only_user, track_id: nil, anomaly: true, timestamp: 1.day.ago.to_i)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  it 'schedules a backfill of the last twelve months only for users with untracked points in them' do
    freeze_time do
      described_class.perform_now

      expect(Tracks::ThrottledBackfillJob).to have_been_enqueued
        .with(user_with_orphans.id, nil, 12.months.ago.to_i).exactly(:once)
      expect(enqueued_jobs.count { |job| job['job_class'] == 'Tracks::ThrottledBackfillJob' }).to eq(1)
    end
  end

  it 'spreads the scheduled walks over the next hour' do
    freeze_time do
      described_class.perform_now

      job = enqueued_jobs.find { |enqueued| enqueued['job_class'] == 'Tracks::ThrottledBackfillJob' }
      expect(job['scheduled_at']).to be_present
      scheduled_at = Time.zone.parse(job['scheduled_at'])
      expect(scheduled_at).to be > Time.current
      expect(scheduled_at).to be <= 1.hour.from_now
    end
  end

  it 'does not schedule a second walk for a user whose backfill is already running' do
    Tracks::ThrottledBackfillJob.schedule(user_with_orphans)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.perform_now

    expect(Tracks::ThrottledBackfillJob).not_to have_been_enqueued
  end
end
