# frozen_string_literal: true

require 'rails_helper'

# Regression for the `reuse_existing_track` rescue path in Tracks::TrackBuilder.
#
# The tracks unique index `index_tracks_on_user_tracker_start_end_unique` is
# keyed on `(user_id, COALESCE(tracker_id, ''), start_at, end_at)` and
# deliberately admits several tracks for the same `(user_id, start_at, end_at)`
# when `tracker_id` differs. When two racing inserts for the *same* key collide
# on that index, `create_track_from_points` rescues `RecordNotUnique` by calling
# `reuse_existing_track`, whose job is to find the winning row and attach the
# loser's points to it.
#
# Before the fix the rescue looked up the winner with `Track.find_by(user_id:,
# start_at:, end_at:)` — omitting `tracker_id` — so when two same-window
# different-tracker rows coexisted PostgreSQL returned whichever row was lower
# in heap/ctid order (deterministic per dataset), not necessarily the
# same-tracker one. The loser's points were then `update_all`-attached to that
# wrong track, corrupting it.
RSpec.describe 'reuse_existing_track scopes the rescue lookup by tracker_id', :non_transactional do
  let(:user) { create(:user) }

  let(:host_class) do
    Class.new do
      include Tracks::TrackBuilder
      attr_reader :user

      def initialize(user)
        @user = user
      end
    end
  end

  let(:base_ts) { Time.zone.parse('2026-04-01 10:00:00').to_i }
  let(:window_start) { Time.zone.at(base_ts) }
  let(:window_end) { Time.zone.at(base_ts + 60) }

  # Two points spanning the shared window. The point's own `tracker_id` is the
  # raw device name; the track's `tracker_id` is whatever the caller passes to
  # `create_track_from_points` (or `points.first.tracker_id` by default).
  def make_points(point_tracker_id, base_lat)
    Array.new(2) do |i|
      create(
        :point,
        user: user,
        tracker_id: point_tracker_id,
        timestamp: base_ts + (i * 60),
        latitude: base_lat + (i * 0.001),
        longitude: 13.405 + (i * 0.001),
        track_id: nil
      )
    end
  end

  it 'attaches the duplicate attempt to the same-tracker winner, not the lower-ctid different-tracker track' do
    host = host_class.new(user)

    # The OTHER tracker's track is created first, so it occupies the lower
    # ctid — the row the unscoped `find_by(user_id:, start_at:, end_at:)`
    # returned pre-fix when the planner fell back to heap/ctid order. The
    # duplicate attempt below must NOT resolve to this track.
    other_points = make_points('device-other', 52.5)
    other_track = host.create_track_from_points(other_points, 1000, skip_segment_detection: true)
    expect(other_track).to be_persisted
    expect(other_track.tracker_id).to eq('device-other')

    # Same window, different tracker_id — the unique index admits both rows,
    # so both tracks coexist (the precondition documented by
    # `tracks_unique_index_allows_multi_device_same_window_spec`).
    same_points = make_points('device-same', 40.0)
    same_track = host.create_track_from_points(same_points, 1000, skip_segment_detection: true)
    expect(same_track).to be_persisted
    expect(same_track.tracker_id).to eq('device-same')

    coexisting = Track.where(user_id: user.id, start_at: window_start, end_at: window_end)
    expect(coexisting.count).to eq(2)
    expect(coexisting.pluck(:tracker_id)).to contain_exactly('device-other', 'device-same')

    # A racing duplicate of the SAME-tracker track collides on
    # (user_id, tracker_id, start_at, end_at) and takes the rescue path. The
    # points span the exact same window as `same_track` so the unique index
    # rejects the new insert.
    dup_points = make_points('device-same', 48.0)
    result = host.create_track_from_points(
      dup_points, 1000,
      tracker_id: 'device-same',
      skip_segment_detection: true
    )

    # The rescue must pick the SAME-tracker winner.
    expect(result.id).to eq(same_track.id)
    expect(result.tracker_id).to eq('device-same')

    # The duplicate's points land on the same-tracker track, never on the
    # different-tracker one.
    expect(Point.where(id: dup_points.map(&:id)).pluck(:track_id).uniq).to eq([same_track.id])
    expect(Point.where(id: dup_points.map(&:id), track_id: other_track.id).count).to eq(0)

    # The other tracker's track is left untouched.
    expect(Point.where(id: other_points.map(&:id)).pluck(:track_id).uniq).to eq([other_track.id])
    expect(other_track.reload.points.count).to eq(2)
  end
end
