# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Driving with zero reported velocity' do
  let(:user) { create(:user) }
  let(:start_at) { Time.zone.parse('2026-01-05 09:00 UTC') }

  def synthetic_track(longitude_step:)
    # Invented coordinates in the open South Pacific, unrelated to any real trip.
    coordinates = Array.new(21) { |i| "#{-140.0 + (i * longitude_step)} -40.0" }
    track = create(:track, user: user, start_at: start_at, end_at: start_at + 600,
                           original_path: "LINESTRING(#{coordinates.join(', ')})")
    now = Time.current
    Point.insert_all!(coordinates.each_with_index.map do |coordinate, i|
      {
        user_id: user.id, track_id: track.id, timestamp: start_at.to_i + (i * 30),
        lonlat: "SRID=4326;POINT(#{coordinate})", velocity: '0.0', accuracy: 5,
        created_at: now, updated_at: now
      }
    end)
    track
  end

  it 'classifies clear driving displacement as driving despite reported zero speeds' do
    track = synthetic_track(longitude_step: 0.0041)
    rows = TransportationModes::FeatureExtractor.call(track.id)

    expect(rows.map { |row| row[:velocity] }.uniq).to eq([0.0])
    expect(rows.drop(1)).to all(satisfy { |row| row[:dist_m] / row[:dt] * 3.6 > 40 })

    segments = TransportationModes::Detector.new(track, fallback: false).call

    expect(segments.sum { |segment| segment[:distance] }).to be > 6_000
    expect(segments.map { |segment| segment[:mode] }.uniq).to eq([:driving])
  end

  it 'keeps genuinely parked points with zero reported speeds stationary' do
    track = synthetic_track(longitude_step: 0.0)

    segments = TransportationModes::Detector.new(track, fallback: false).call

    expect(segments.map { |segment| segment[:mode] }.uniq).to eq([:stationary])
    expect(segments.sum { |segment| segment[:distance] }).to eq(0)
  end
end
