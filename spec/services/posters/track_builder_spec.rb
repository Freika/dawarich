# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Posters::TrackBuilder do
  let(:user) { create(:user) }
  let(:start_at) { Time.zone.parse('2026-04-01T00:00:00Z') }
  let(:end_at) { Time.zone.parse('2026-04-02T00:00:00Z') }

  def build_track
    described_class.new(user:, start_at:, end_at:).call
  end

  def create_point(lon, lat, time)
    create(:point, user:, lonlat: "POINT(#{lon} #{lat})", timestamp: time.to_i)
  end

  it 'returns nil when there are no points in range' do
    create_point(13.40, 52.51, start_at - 1.day)

    expect(build_track).to be_nil
  end

  it 'returns a MultiLineString ordered by timestamp with [lon, lat] pairs' do
    create_point(13.41, 52.52, start_at + 2.minutes)
    create_point(13.40, 52.51, start_at + 1.minute)

    track = build_track

    expect(track['type']).to eq('MultiLineString')
    expect(track['coordinates']).to eq([[[13.40, 52.51], [13.41, 52.52]]])
  end

  it 'splits segments on gaps longer than one hour' do
    create_point(13.40, 52.51, start_at)
    create_point(13.41, 52.52, start_at + 10.minutes)
    create_point(13.50, 52.55, start_at + 3.hours)
    create_point(13.51, 52.56, start_at + 3.hours + 10.minutes)

    track = build_track

    expect(track['coordinates'].size).to eq(2)
  end

  it 'drops single-point segments' do
    create_point(13.40, 52.51, start_at)
    create_point(13.50, 52.55, start_at + 3.hours)
    create_point(13.51, 52.56, start_at + 3.hours + 10.minutes)

    track = build_track

    expect(track['coordinates'].size).to eq(1)
    expect(track['coordinates'].first.size).to eq(2)
  end

  it 'returns nil when only isolated points exist' do
    create_point(13.40, 52.51, start_at)
    create_point(13.50, 52.55, start_at + 3.hours)

    expect(build_track).to be_nil
  end

  it 'keeps every point without sampling' do
    stub_const('Posters::TrackBuilder::MAX_POINTS', 5) if defined?(Posters::TrackBuilder::MAX_POINTS)
    10.times { |i| create_point(13.40 + (i * 0.001), 52.51, start_at + i.minutes) }

    track = build_track

    expect(track['coordinates'].sum(&:size)).to eq(10)
  end

  it 'excludes anomalies' do
    create_point(13.40, 52.51, start_at)
    create_point(13.41, 52.52, start_at + 1.minute)
    create(:point, user:, lonlat: 'POINT(0.0 0.0)', timestamp: (start_at + 2.minutes).to_i, anomaly: true)

    track = build_track

    expect(track['coordinates'].first.size).to eq(2)
  end
end
