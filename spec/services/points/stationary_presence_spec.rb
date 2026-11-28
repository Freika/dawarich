# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stationary presence observations' do
  let(:user) { create(:user) }
  let(:track) { create(:track, user:) }
  let(:start_time) { Time.utc(2026, 10, 27, 12).to_i }

  before do
    create(:point, user:, track:, longitude: 13.0, latitude: 52.0, timestamp: start_time)
    create(:point, user:, track:, longitude: 13.1, latitude: 52.1, timestamp: start_time + 120,
                   motion_data: { action: 'stationary_presence' })
    create(:point, user:, track:, longitude: 13.001, latitude: 52.0, timestamp: start_time + 240)
  end

  it 'retains presence for visit detection without adding distance' do
    expect(user.points.not_anomaly.count).to eq(3)
    expect(Point.total_distance(user.points, :m)).to be_between(68, 70)
    expect(Point.calculate_distance_for_array_geocoder(user.points.order(:timestamp).to_a, :m)).to be_between(68, 70)
    distances = Stats::DailyDistanceQuery.new(user.points, Date.new(2026, 10, 27)..Date.new(2026, 10, 27), 'UTC').call
    expect(distances).to eq([[27, 69]])
  end

  it 'does not suppress imported or sensor-reported still movement without the explicit presence action' do
    ordinary = create(:point, user:, longitude: 13.002, latitude: 52.0, timestamp: start_time + 300,
                              motion_data: { motion: ['stationary'] })
    expect(user.points.route_observations).to include(ordinary)
  end

  it 'omits only explicit presence from rebuilt and clipped route geometry' do
    track.recalculate_path_and_distance!
    Tracks::Recalculator.call(track, broadcast: false)
    expect(track.distance).to be_between(68, 70)
    expect(track.original_path.points.map { |point| [point.x, point.y] }).to eq([[13.0, 52.0], [13.001, 52.0]])
    summary = Tracks::PointGeometryQuery.new(points_scope: user.points).summary_for(track_id: track.id)
    expect(summary[:geometry][:coordinates]).to eq([[13.0, 52.0], [13.001, 52.0]])
    expect(user.points.count).to eq(3)
  end
end
