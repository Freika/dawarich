# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BoundaryDetector under unique-index conflict', :non_transactional do
  let(:user) { create(:user) }

  let(:p1_ts) { Time.zone.parse('2026-04-01 10:00:00') }
  let(:p2_ts) { Time.zone.parse('2026-04-01 10:05:00') }
  let(:p3_ts) { Time.zone.parse('2026-04-01 10:08:00') }
  let(:p4_ts) { Time.zone.parse('2026-04-01 10:12:00') }

  let(:tracker_id) { 'iphone' }

  def make_point(timestamp:, lat:, lon:, track: nil)
    create(
      :point,
      user: user,
      timestamp: timestamp.to_i,
      latitude: lat,
      longitude: lon,
      altitude: 50,
      tracker_id: tracker_id,
      track_id: track&.id
    )
  end

  def make_track(points:)
    Track.create!(
      user_id: user.id,
      tracker_id: tracker_id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: 'LINESTRING(13.4 52.5, 13.41 52.51)',
      distance: 100,
      duration: (points.last.timestamp - points.first.timestamp),
      avg_speed: 10
    ).tap do |track|
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    end
  end

  it 'preserves boundary tracks when merged span collides with a third-party track' do
    older_points = [
      make_point(timestamp: p1_ts, lat: 52.5, lon: 13.4),
      make_point(timestamp: p2_ts, lat: 52.51, lon: 13.41)
    ]
    newer_points = [
      make_point(timestamp: p3_ts, lat: 52.52, lon: 13.42),
      make_point(timestamp: p4_ts, lat: 52.53, lon: 13.43)
    ]
    older = make_track(points: older_points)
    newer = make_track(points: newer_points)

    third_party = Track.create!(
      user_id: user.id,
      tracker_id: tracker_id,
      start_at: p1_ts,
      end_at: p4_ts,
      original_path: 'LINESTRING(13.4 52.5, 13.43 52.53)',
      distance: 500,
      duration: (p4_ts - p1_ts).to_i,
      avg_speed: 10
    )

    detector = Tracks::BoundaryDetector.new(user)
    result = detector.send(:merge_boundary_tracks, [older, newer])

    expect(result).to be false
    expect(Track.where(id: older.id)).to exist
    expect(Track.where(id: newer.id)).to exist
    expect(Track.where(id: third_party.id)).to exist

    older_point_ids = older_points.map(&:id)
    newer_point_ids = newer_points.map(&:id)
    expect(Point.where(id: older_point_ids).pluck(:track_id).uniq).to eq([older.id])
    expect(Point.where(id: newer_point_ids).pluck(:track_id).uniq).to eq([newer.id])
    expect(third_party.reload.points.count).to eq(0)
  end

  it 'preserves originals if the merged track creation produces nothing' do
    older_points = [
      make_point(timestamp: p1_ts, lat: 52.5, lon: 13.4),
      make_point(timestamp: p2_ts, lat: 52.51, lon: 13.41)
    ]
    newer_points = [
      make_point(timestamp: p3_ts, lat: 52.52, lon: 13.42),
      make_point(timestamp: p4_ts, lat: 52.53, lon: 13.43)
    ]
    older = make_track(points: older_points)
    newer = make_track(points: newer_points)

    detector = Tracks::BoundaryDetector.new(user)
    allow(detector).to receive(:create_track_from_points).and_return(nil)

    result = detector.send(:merge_boundary_tracks, [older, newer])

    expect(result).to be false
    expect(Track.where(id: older.id)).to exist
    expect(Track.where(id: newer.id)).to exist
  end
end
