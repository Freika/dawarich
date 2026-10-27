# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::VectorTileQuery do
  let(:user) { create(:user) }
  let!(:track) do
    # Made-up ocean coordinates: a short path across the date line.
    create(:track, user:, original_path: 'LINESTRING(179.2 -24.6, -179.1 -24.6)',
                   dominant_mode: :flying, start_at: Time.utc(2026, 1, 1),
                   end_at: Time.utc(2026, 1, 1, 0, 30),
                   distance: 172_000, avg_speed: 344, duration: 1800)
  end

  it 'keeps a date-line crossing short while retaining both sides in the world tile' do
    rows = described_class.new(scope: user.tracks, z: 0, x: 0, y: 0).feature_rows

    expect(rows.map { |row| row['id'].to_i }).to eq([track.id])

    bounds = measurements(rows.first['geom'])

    # MVT coordinates span 4096 units across the world. A 1.7-degree crossing
    # needs about 20 units in total, split between the two map edges.
    expect(bounds['length'].to_f).to be < 64
    expect(bounds['xmin'].to_f).to be < 16
    expect(bounds['xmax'].to_f).to be > 4080
  end

  it 'does not draw the date-line crossing through a central longitude tile' do
    # z3/x4/y4 covers 0..45 degrees east and 0..41 degrees south.
    result = described_class.new(scope: user.tracks, z: 3, x: 4, y: 4).call

    expect(result.feature_count).to eq(0)
    # select_one returns PostgreSQL bytea as hex text, including "\\x" for empty bytes.
    expect(PG::TextDecoder::Bytea.new.decode(result.tile)).to be_blank
  end

  it 'preserves the geometry of a wide track that never crosses the seam' do
    path = "LINESTRING(#{(-680..680).map { |step| "#{step * 0.25} -24.6" }.join(', ')})"
    track.update!(original_path: path, dominant_mode: :walking, avg_speed: 5)
    row = described_class.new(scope: user.tracks, z: 0, x: 0, y: 0).feature_rows.fetch(0)
    original = "ST_AsMVTGeom(ST_Simplify(ST_Transform(#{GreatCircleSql.densified('original_path')}, 3857), " \
               "#{described_class::WEB_MERCATOR_WORLD / described_class::TILE_PIXELS}), " \
               'ST_TileEnvelope(0, 0, 0), 4096, 256, true)'
    sql = "SELECT ST_AsEWKB(?::geometry) = ST_AsEWKB(#{original}) FROM tracks WHERE id = ?"
    unchanged = Track.connection.select_value(Track.sanitize_sql_array([sql, row['geom'], track.id]))

    expect(unchanged).to be(true)
  end

  def measurements(geometry)
    sql = <<~SQL
      SELECT ST_Length(geom) AS length, ST_XMin(geom) AS xmin, ST_XMax(geom) AS xmax,
             ST_NumGeometries(geom) AS parts FROM (SELECT ?::geometry AS geom) AS measured
    SQL
    Track.connection.select_one(Track.sanitize_sql_array([sql, geometry]))
  end

  [-180.0, 180.0].each do |seam|
    it "splits a crossing containing a vertex exactly at #{seam}" do
      track.update!(original_path: "LINESTRING(179.2 -24.6, #{seam} -24.6, -179.1 -24.6)")
      row = described_class.new(scope: user.tracks, z: 0, x: 0, y: 0).feature_rows.fetch(0)
      bounds = measurements(row['geom'])

      expect(bounds['length'].to_f).to be < 64
      expect(bounds['xmin'].to_f).to eq(0)
      expect(bounds['xmax'].to_f).to eq(4096)
    end
  end

  it 'splits a dense ground track that crosses the seam three times' do
    path = 'LINESTRING(179.6 -24.6, 179.8 -24.6, -179.9 -24.6, -179.6 -24.6, ' \
           '-179.8 -24.5, 179.9 -24.5, 179.6 -24.5, 179.8 -24.4, -179.9 -24.4, -179.6 -24.4)'
    track.update!(original_path: path, dominant_mode: :walking, avg_speed: 5)
    row = described_class.new(scope: user.tracks, z: 8, x: 255, y: 146).feature_rows.fetch(0)
    bounds = measurements(row['geom'])

    expect(bounds['xmin'].to_f).to be > 2000
    expect(bounds['xmax'].to_f).to eq(4096)
    expect(bounds['parts'].to_i).to eq(2)
    expect(described_class.new(scope: user.tracks, z: 8, x: 128, y: 146).call.feature_count).to eq(0)
  end

  [0, 7].each do |edge|
    it "retains the crossing up to the seam in edge tile z3/x#{edge}" do
      row = described_class.new(scope: user.tracks, z: 3, x: edge, y: 4).feature_rows.fetch(0)
      bounds = measurements(row['geom'])

      expect(bounds['length'].to_f).to be < 128
      expect(bounds[edge.zero? ? 'xmin' : 'xmax'].to_f).to eq(edge.zero? ? 0 : 4096)
    end
  end

  it 'splits a clipped track path at the seam' do
    [179.2, -179.1].each_with_index do |longitude, index|
      create(:point, user:, track:, longitude:, latitude: -24.6, timestamp: track.start_at.to_i + index * 600)
    end
    query = described_class.new(scope: user.tracks, clip_points_scope: user.points, z: 0, x: 0, y: 0)

    expect(measurements(query.feature_rows.fetch(0)['geom'])['length'].to_f).to be < 64
  end

  it 'keeps speed tiles short on both sides without drawing through a central tile' do
    [179.2, -179.1].each_with_index do |longitude, index|
      create(:point, user:, track:, longitude:, latitude: -24.6, timestamp: track.start_at.to_i + index * 600)
    end
    query = ->(z, x, y) { Tracks::SpeedVectorTileQuery.new(scope: user.tracks, points_scope: user.points, z:, x:, y:) }
    bounds = measurements(query.call(0, 0, 0).feature_rows.fetch(0)['geom'])

    expect(bounds['length'].to_f).to be < 64
    expect(bounds['parts'].to_i).to eq(2)
    expect(bounds['xmin'].to_f).to eq(0)
    expect(bounds['xmax'].to_f).to eq(4096)
    expect(query.call(8, 128, 146).call.feature_count).to eq(0)
    [0, 255].each do |edge|
      row = query.call(8, edge, 146).feature_rows.fetch(0)
      bounds = measurements(row['geom'])
      expect(row['segment_speed']).to be_present
      expect(bounds['length'].to_f).to be < 3000
      expect(bounds[edge.zero? ? 'xmin' : 'xmax'].to_f).to eq(edge.zero? ? 0 : 4096)
    end
  end

  it 'keeps trip route tiles short on both sides without drawing through a central tile' do
    trip = create(:trip, user:, started_at: track.start_at, ended_at: track.end_at, path: nil,
                         skip_calculation_enqueue: true)
    query = ->(z, x, y) { Trips::RoutesTileQuery.new(trip:, points_scope: user.points, timezone: 'UTC', z:, x:, y:) }
    world = query.call(0, 0, 0)
    geometry = Track.connection.select_value(
      "#{world.send(:with_clause)} SELECT #{world.send(:mvt_geom, 'source_geom')} FROM visible_features"
    )
    bounds = measurements(geometry)

    expect(world.call.feature_count).to eq(1)
    expect(bounds['length'].to_f).to be < 64
    expect(bounds['parts'].to_i).to eq(2)
    expect(bounds['xmin'].to_f).to eq(0)
    expect(bounds['xmax'].to_f).to eq(4096)
    expect(query.call(3, 4, 4).call.feature_count).to eq(0)
  end

  it 'preserves a prime-meridian crossing in a track that also crosses the date line' do
    coordinates = (-680..718).map { |step| "#{step * 0.25} -24.6" }
    coordinates << '-179.5 -24.6'
    track.update!(original_path: "LINESTRING(#{coordinates.join(', ')})")
    row = described_class.new(scope: user.tracks, z: 0, x: 0, y: 0).feature_rows.fetch(0)
    bounds = measurements(row['geom'])

    expect(bounds['length'].to_f).to be_between(3900, 4100)
    expect(bounds['parts'].to_i).to eq(2)
  end
end
