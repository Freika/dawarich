# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculatePerTrackerTracksJob do
  describe 'no argument: enqueueing pending users' do
    let(:user_with_nil_tracker) { create(:user) }
    let(:user_with_tagged_tracker) { create(:user) }
    let(:user_without_tracks) { create(:user) }

    before do
      create(:track, user: user_with_nil_tracker, tracker_id: nil)
      create(:track, user: user_with_tagged_tracker, tracker_id: 'iphone')
    end

    it 'enqueues only users with at least one NULL tracker_id track' do
      expect do
        described_class.perform_now
      end.to have_enqueued_job(described_class).with(user_with_nil_tracker.id).exactly(:once)

      expect(described_class).not_to have_been_enqueued.with(user_with_tagged_tracker.id)
      expect(described_class).not_to have_been_enqueued.with(user_without_tracks.id)
    end

    it 'staggers per-user enqueues with a wait between 0 and STAGGER_WINDOW_SECONDS' do
      described_class.perform_now

      scheduled = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
        job[:job] == described_class
      end

      expect(scheduled).not_to be_empty

      scheduled.each do |job|
        delta = job[:at].to_f - Time.current.to_f
        expect(delta).to be >= 0
        expect(delta).to be <= described_class::STAGGER_WINDOW_SECONDS + 5
      end
    end

    it 'is idempotent: a second run still only enqueues remaining nil-tracker users' do
      described_class.perform_now
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect do
        described_class.perform_now
      end.to have_enqueued_job(described_class).with(user_with_nil_tracker.id).exactly(:once)
    end

    it 'skips entirely when no user has nil tracker tracks' do
      Track.where(tracker_id: nil).update_all(tracker_id: 'backfilled')

      expect do
        described_class.perform_now
      end.not_to have_enqueued_job(described_class)
    end

    it 'enqueues users whose points still carry a legacy importer constant' do
      Track.where(tracker_id: nil).update_all(tracker_id: 'backfilled')
      user_with_legacy_points = create(:user)
      create(:point, user: user_with_legacy_points, tracker_id: 'google-maps-timeline-export')

      expect do
        described_class.perform_now
      end.to have_enqueued_job(described_class).with(user_with_legacy_points.id).exactly(:once)
    end
  end

  describe 'with user_id: processing one user' do
    let(:user) { create(:user) }

    it 'backfills point tracker_ids first, then invokes RecalculateDataJob via the ActiveJob lifecycle' do
      create(:track, user: user, tracker_id: nil)

      backfiller = instance_double(Points::TrackerIdBackfiller, call: 0)
      expect(Points::TrackerIdBackfiller).to receive(:new).with(user).and_return(backfiller)
      expect(Users::RecalculateDataJob).to receive(:perform_now).with(user.id, notify: false)

      described_class.new.perform(user.id)
    end

    it 'skips RecalculateDataJob when no nil-tracker tracks remain after backfill' do
      create(:track, user: user, tracker_id: 'iphone')

      expect(Users::RecalculateDataJob).not_to receive(:perform_now)

      described_class.new.perform(user.id)
    end

    it 'no-ops when the user has been deleted' do
      expect { described_class.new.perform(-1) }.not_to raise_error
    end
  end

  describe 'end-to-end: legacy NULL-tracker points get backfilled and a re-run gives non-NULL tracks' do
    let(:user) do
      create(:user, settings: {
               'minutes_between_routes' => 30,
               'meters_between_routes' => 500
             })
    end
    let(:base_time) { 1.hour.ago.to_i }

    before do
      6.times do |i|
        create(
          :point,
          user: user,
          tracker_id: nil,
          raw_data: { 'deviceTag' => 1_111_111_111 },
          timestamp: base_time + (i * 60),
          lonlat: "POINT(#{13.405 + (i * 0.0001)} #{52.52 + (i * 0.0001)})"
        )
      end

      create(:track, user: user, tracker_id: nil)
    end

    it 'after the per-user job runs, points carry the derived tracker_id' do
      described_class.new.perform(user.id)

      tracker_ids = user.points.reload.pluck(:tracker_id).uniq
      expect(tracker_ids).to eq(['google-records-device-1111111111'])
    end
  end
end
