# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::SpeedVectorTileQuery do
  let(:user) { create(:user) }
  let(:start_at) { Time.utc(2024, 6, 1, 10) }

  def track_with_points(longitudes: [0.001, 0.002, 0.0021], offsets: [0, 10, 20])
    path = "LINESTRING(#{longitudes.map { |longitude| "#{longitude} 0.001" }.join(', ')})"
    create(:track, user:, original_path: path, start_at:, end_at: start_at + 1.hour).tap do |track|
      longitudes.zip(offsets).each do |longitude, offset|
        create(:point, user:, track:, longitude:, latitude: 0.001, timestamp: start_at.to_i + offset)
      end
    end
  end

  def query(points_scope: user.points, **coordinates)
    described_class.new(scope: user.tracks, points_scope:, z: 15, x: 16_384, y: 16_383, **coordinates)
  end

  it 'colors the slow part independently while preserving track popup properties' do
    track = track_with_points

    rows = query.feature_rows

    expect(rows.size).to eq(2)
    expect(rows.map { |row| row['segment_speed'] }.sort)
      .to match([be_within(0.05).of(4.0), be_within(0.05).of(40.0)])
    expect(rows.map { |row| row['id'] }.uniq).to eq([track.id])
    expect(rows.map { |row| row['avg_speed'] }.uniq).to eq([track.avg_speed])
    expect(query.call.feature_count).to eq(2)
  end

  it 'keeps the connecting segment when both endpoints are beyond the tile buffer' do
    track_with_points(longitudes: [-0.01, 0.03], offsets: [0, 300])

    rows = query.feature_rows

    expect(rows.size).to eq(1)
    expect(rows.first['segment_speed']).to be_within(0.5).of(53.4)
  end

  it 'caps implausible speed and handles identical timestamps without dividing by zero' do
    track_with_points(offsets: [0, 0, 0])
    expect(query.feature_rows.map { |row| row['segment_speed'] }).to eq([0])

    user.points.order(:id).last.update!(timestamp: start_at.to_i + 1)
    user.points.order(:id).last.update!(lonlat: 'POINT(0.003 0.001)')
    expect(query.feature_rows.map { |row| row['segment_speed'] }).to include(150)
  end

  it 'honors point visibility and does not reconnect through excluded points' do
    track_with_points
    restricted = user.points.where(timestamp: (start_at.to_i + 10)..)

    rows = query(points_scope: restricted).feature_rows

    expect(rows.size).to eq(1)
    expect(rows.first['segment_speed']).to be_within(0.05).of(4.0)
  end

  it 'does not use another user\'s point even if it references the selected track' do
    track = track_with_points
    create(:point, user: create(:user), track:, longitude: 0.004, latitude: 0.001,
                   timestamp: start_at.to_i + 5)

    expect(query.feature_rows.map { |row| row['segment_speed'] }.sort)
      .to match([be_within(0.05).of(4.0), be_within(0.05).of(40.0)])
  end

  it 'retains a flat track when its recording points are unavailable' do
    create(:track, user:, original_path: 'LINESTRING(0.001 0.001, 0.002 0.001)')

    rows = query.feature_rows

    expect(rows.size).to eq(1)
    expect(rows.first['segment_speed']).to be_nil
  end

  it 'preserves a visible walking route whose individual segments are smaller than a tile pixel' do
    longitudes = (0..600).map { |index| 0.001 + (index * 0.00001) }
    path = "LINESTRING(#{longitudes.map { |longitude| "#{longitude} 0.001" }.join(', ')})"
    track = create(:track, user:, original_path: path, start_at:, end_at: start_at + 600)
    Point.insert_all!(longitudes.each_with_index.map do |longitude, index|
      { user_id: user.id, track_id: track.id, timestamp: start_at.to_i + index,
        lonlat: "POINT(#{longitude} 0.001)", created_at: start_at, updated_at: start_at }
    end)

    rows = query(z: 8, x: 128, y: 127).feature_rows

    expect(rows.size).to eq(1)
    expect(rows.first['segment_speed']).to eq(4)
    expect(query(z: 8, x: 128, y: 127).call.tile).to be_present
  end

  it 'uses the flat overview below the classic speed-color zoom threshold' do
    track_with_points(longitudes: [0.001, 0.02, 0.03])

    rows = query(z: 7, x: 64, y: 63).feature_rows

    expect(rows.size).to eq(1)
    expect(rows.first).not_to have_key('segment_speed')
  end

  it 'rejects a tile over capacity instead of presenting a partial route as complete' do
    track_with_points
    stub_const('Tracks::SpeedVectorTileQuery::MAX_SPEED_FEATURES_PER_TILE', 1)

    expect { query.call }.to raise_error(described_class::FeatureLimitError)
  end

  it 'applies the statement timeout to the point scan too' do
    track_with_points
    allow(VectorTileTimeout).to receive(:query_timeout_ms).and_return(50)
    slow_points = user.points.where('(SELECT pg_sleep(0.3)) IS NOT NULL')

    expect { query(points_scope: slow_points).call }.to raise_error(ActiveRecord::QueryCanceled)
  end
end
