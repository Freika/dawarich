# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Boundary merges skip only a gap that holds a kept track of the same device' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }
  let(:base) { 3.days.ago.beginning_of_hour.to_i }

  def points_at(offsets, tracker_id:, import_id: nil)
    offsets.map do |offset|
      create(:point, user: user, tracker_id: tracker_id, import_id: import_id, timestamp: base + offset,
                     lonlat: "POINT(#{13.4 + (offset * 0.00001)} 52.5)")
    end
  end

  def track_over(points, **attrs)
    track = create(:track, user: user, tracker_id: points.first.tracker_id,
                           start_at: Time.zone.at(points.first.timestamp),
                           end_at: Time.zone.at(points.last.timestamp), **attrs)
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)
    track
  end

  def kept_track(offsets, tracker_id:)
    track_over(points_at(offsets, tracker_id: tracker_id, import_id: import.id),
               import_id: import.id, tracker_id: "import-#{import.id}-activity-#{offsets.first}",
               created_at: 3.hours.ago)
  end

  let!(:earlier) { track_over(points_at([0, 60, 120, 180], tracker_id: 'phone')) }
  let!(:later) { track_over(points_at([480, 540, 600, 660], tracker_id: 'phone')) }

  def resolve
    Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks
  end

  def merged?
    phone_tracks = user.tracks.where(tracker_id: 'phone')
    !phone_tracks.exists?(id: [earlier.id, later.id]) &&
      phone_tracks.where(start_at: Time.zone.at(base), end_at: Time.zone.at(base + 660)).exists?
  end

  it 'merges across a kept track recorded by another device' do
    kept_track([240, 300, 360, 420], tracker_id: 'watch')

    resolve

    expect(merged?).to be(true)
  end

  it 'merges when a kept track of the same device overlaps a member but not the gap' do
    kept_track([-300, -200, -100, 30], tracker_id: 'phone')

    resolve

    expect(merged?).to be(true)
  end

  it 'merges across untracked points of the same device' do
    points_at([240, 300, 360, 420], tracker_id: 'phone')

    resolve

    expect(merged?).to be(true)
  end

  it 'does not merge across a kept track of the same device inside the gap' do
    kept = kept_track([240, 300, 360, 420], tracker_id: 'phone')

    resolve

    expect(merged?).to be(false)
    expect(user.tracks.where(id: [earlier.id, later.id, kept.id]).count).to eq(3)
  end
end
