# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260508193900_dedupe_tracks_for_unique_index')

RSpec.describe DedupeTracksForUniqueIndex do
  let(:user) { create(:user) }
  let(:start_at) { Time.zone.parse('2026-04-01 10:00:00') }
  let(:end_at) { Time.zone.parse('2026-04-01 10:30:00') }

  before do
    ActiveRecord::Base.connection.execute(
      'DROP INDEX IF EXISTS index_tracks_on_user_start_end_unique'
    )
    ActiveRecord::Base.connection.execute(
      'DROP INDEX IF EXISTS index_tracks_on_user_tracker_start_end_unique'
    )
  end

  def make_track(distance: 100)
    Track.create!(
      user_id: user.id,
      start_at: start_at,
      end_at: end_at,
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: distance,
      duration: (end_at - start_at).to_i,
      avg_speed: 10
    )
  end

  it 'keeps the newest track (highest id) and deletes the rest' do
    older = make_track(distance: 1000)
    middle = make_track(distance: 500)
    newest = make_track(distance: 100)

    described_class.new.up

    expect(Track.where(id: newest.id)).to exist
    expect(Track.where(id: [older.id, middle.id])).to be_empty
  end

  it 'deletes track_segments belonging to loser tracks' do
    loser = make_track(distance: 1000)
    winner = make_track(distance: 100)
    loser_segment = create(:track_segment, track: loser)
    winner_segment = create(:track_segment, track: winner)

    described_class.new.up

    expect(TrackSegment.where(id: loser_segment.id)).to be_empty
    expect(TrackSegment.where(id: winner_segment.id)).to exist
  end

  it 'is a no-op when no duplicates exist' do
    make_track(distance: 100)

    expect { described_class.new.up }.not_to(change { Track.count })
  end

  it 'does not affect tracks belonging to other users' do
    other_user = create(:user)
    other_track = Track.create!(
      user_id: other_user.id,
      start_at: start_at,
      end_at: end_at,
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: 500,
      duration: 1800,
      avg_speed: 10
    )

    make_track(distance: 1000)
    make_track(distance: 100)

    described_class.new.up

    expect(Track.where(id: other_track.id)).to exist
  end

  it 'is idempotent — re-running after a successful run is a no-op' do
    make_track(distance: 1000)
    make_track(distance: 100)

    described_class.new.up
    expect { described_class.new.up }.not_to(change { Track.count })
  end
end
