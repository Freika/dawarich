# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::FeatureExtractor do
  let(:user) { create(:user) }
  let(:track) { create(:track, user: user) }

  # ~100 m due east of the base point at Leipzig's latitude
  let(:base_lat) { 51.3402 }
  let(:base_lon) { 12.3712 }
  let(:east_lon) { base_lon + (100.0 / (111_320.0 * Math.cos(base_lat * Math::PI / 180))) }

  before do
    now = Time.current
    Point.insert_all(
      [
        { user_id: user.id, track_id: track.id, timestamp: 1_000,
          lonlat: "SRID=4326;POINT(#{base_lon} #{base_lat})", accuracy: 5.0, velocity: '1.5',
          motion_data: { 'motion' => ['walking'] }, created_at: now, updated_at: now },
        { user_id: user.id, track_id: track.id, timestamp: 1_010,
          lonlat: "SRID=4326;POINT(#{east_lon} #{base_lat})", accuracy: 8.0, velocity: '',
          motion_data: {}, created_at: now, updated_at: now },
        { user_id: user.id, track_id: track.id, timestamp: 1_010,
          lonlat: "SRID=4326;POINT(#{east_lon} #{base_lat + 0.00001})", accuracy: nil, velocity: nil,
          motion_data: {}, created_at: now, updated_at: now }
      ]
    )
  end

  it 'returns ordered per-point primitives from one SQL pass' do
    rows = described_class.call(track.id)

    expect(rows.size).to eq(3)
    expect(rows.first[:dt]).to be_nil
    expect(rows.first[:dist_m]).to be_nil
    expect(rows.first[:velocity]).to eq(1.5)
    expect(rows.first[:motion_data]).to eq('motion' => ['walking'])
    expect(rows.first[:lat]).to be_within(0.0001).of(base_lat)
    expect(rows.first[:lon]).to be_within(0.0001).of(base_lon)

    expect(rows[1][:dt]).to eq(10)
    expect(rows[1][:dist_m]).to be_within(1.0).of(100.0)
    expect(rows[1][:bearing_deg]).to be_within(2.0).of(90.0)
    expect(rows[1][:velocity]).to be_nil

    expect(rows[2][:dt]).to eq(0)
    expect(rows[2][:motion_data]).to eq({})
  end

  it 'never exposes raw_data' do
    rows = described_class.call(track.id)
    expect(rows.first).not_to have_key(:raw_data)
  end

  it 'excludes anomaly-flagged points, matching the track builder' do
    now = Time.current
    Point.insert_all(
      [{ user_id: user.id, track_id: track.id, timestamp: 1_020, anomaly: true,
         lonlat: "SRID=4326;POINT(#{base_lon} #{base_lat + 0.5})", accuracy: 5.0, velocity: '99.0',
         motion_data: {}, created_at: now, updated_at: now }]
    )

    rows = described_class.call(track.id)

    expect(rows.size).to eq(3)
    expect(rows.map { |r| r[:ts] }).not_to include(1_020)
  end
end
