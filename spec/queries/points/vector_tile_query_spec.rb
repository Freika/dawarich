# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::VectorTileQuery do
  let(:user) { create(:user) }

  # Coordinates are derived from web-mercator meters so fixtures stay correct
  # relative to the decimation grid, whatever the tier constants become.
  def lonlat_at(east, north)
    row = ActiveRecord::Base.connection.select_one(
      "SELECT ST_X(p) AS lon, ST_Y(p) AS lat FROM (
         SELECT ST_Transform(ST_SetSRID(ST_MakePoint(#{east}, #{north}), 3857), 4326) AS p
       ) s"
    )
    [row['lon'].to_f, row['lat'].to_f]
  end

  def create_point_at(east, north, attrs = {})
    lon, lat = lonlat_at(east, north)
    create(:point, user:, longitude: lon, latitude: lat,
                   lonlat: "POINT(#{lon} #{lat})", **attrs)
  end

  def feature_rows(z:, x:, y:) # rubocop:disable Naming/MethodParameterName
    described_class.new(scope: user.points, z: z, x: x, y: y).feature_rows
  end

  describe 'decimation grid' do
    # z10 tile (512, 511) and z14 tile (8192, 8191) both have their south-west
    # corner at the web-mercator origin, so offsets in meters are cell-aligned.
    before do
      create_point_at(10, 10)
      create_point_at(30, 10)
      create_point_at(2_000, 10)
    end

    it 'merges points closer than the cell into one feature with a count' do
      rows = feature_rows(z: 10, x: 512, y: 511)

      # z10 cell ≈ 153m: the 10m/30m pair merges, the 2km point stays alone
      expect(rows.size).to eq(2)
      merged = rows.find { |r| r['count'].to_i == 2 }
      expect(merged).to be_present
    end

    it 'keeps the same points separate at a zoom whose cell is smaller than their spacing' do
      rows = feature_rows(z: 14, x: 8192, y: 8191)

      # z14 cell ≈ 4.8m: 20m apart no longer merges
      expect(rows.size).to eq(3)
      expect(rows.map { |r| r['count'].to_i }).to all(eq(1))
    end

    it 'picks the lowest id as the deterministic representative of a merged cell' do
      rows = feature_rows(z: 10, x: 512, y: 511)
      merged = rows.find { |r| r['count'].to_i == 2 }

      expect(merged['id'].to_i).to eq(user.points.order(:id).first.id)
    end
  end

  describe 'emitted coordinates' do
    it 'carries the stored ST_Y/ST_X values as latitude/longitude properties' do
      point = create_point_at(10, 10)

      rows = feature_rows(z: 10, x: 512, y: 511)

      stored = ActiveRecord::Base.connection.select_one(
        "SELECT ST_Y(lonlat::geometry) AS lat, ST_X(lonlat::geometry) AS lon
         FROM points WHERE id = #{point.id}"
      )
      expect(rows.first['latitude'].to_f).to be_within(1e-9).of(stored['lat'].to_f)
      expect(rows.first['longitude'].to_f).to be_within(1e-9).of(stored['lon'].to_f)
    end
  end

  describe 'low-zoom aggregate regime' do
    it 'emits only centroid features with counts and no per-point attributes' do
      create_point_at(10, 10)
      create_point_at(30, 10)

      rows = feature_rows(z: 2, x: 2, y: 1)

      expect(rows.size).to eq(1)
      expect(rows.first['count'].to_i).to eq(2)
      expect(rows.first).not_to have_key('id')
      expect(rows.first).not_to have_key('timestamp')
    end

    it 'stays within the low-zoom tier ceiling on a large spread account' do
      now = Time.zone.now
      rows_to_insert = Array.new(10_000) do |i|
        lon = 1 + ((i % 100) * 0.88)
        lat = 1 + ((i / 100) * 0.59)
        { user_id: user.id, timestamp: 2.years.ago.to_i + i,
          lonlat: "POINT(#{lon} #{lat})", created_at: now, updated_at: now }
      end
      Point.insert_all(rows_to_insert)

      query = described_class.new(scope: user.points, z: 2, x: 2, y: 1)
      rows = query.feature_rows

      expect(rows.size).to be <= query.tile_feature_limit
      expect(rows.sum { |r| r['count'].to_i }).to eq(10_000)
    end
  end

  describe 'feature limit' do
    it 'is unreachable by construction for every zoom tier' do
      (0..22).each do |z|
        query = described_class.new(scope: user.points, z: z, x: 0, y: 0)
        max_cells = ((512 * (1 + 2 * described_class::MARGIN)) / query.grid_px)**2

        expect(query.tile_feature_limit).to be > max_cells
      end
    end
  end

  describe 'statement timeout' do
    it 'cancels a query that exceeds QUERY_TIMEOUT_MS via a real statement_timeout' do
      create_point_at(10, 10)
      stub_const('Points::VectorTileQuery::QUERY_TIMEOUT_MS', 50)

      slow_scope = user.points.where('(SELECT pg_sleep(0.3)) IS NOT NULL')

      expect do
        described_class.new(scope: slow_scope, z: 10, x: 512, y: 511).call
      end.to raise_error(ActiveRecord::QueryCanceled)
    end
  end

  describe 'antimeridian seam' do
    it 'keeps a point near +180 visible in the buffer of the x=0 edge tile' do
      lon = 179.9999
      lat = lonlat_at(0, 10)[1]
      create(:point, user:, longitude: lon, latitude: lat, lonlat: "POINT(#{lon} #{lat})")

      home_rows = feature_rows(z: 6, x: 63, y: 31)
      wrapped_rows = feature_rows(z: 6, x: 0, y: 31)

      expect(home_rows.size).to eq(1)
      # The x=0 tile's west buffer crosses the seam; the point must appear there
      # (as buffer content), not be dropped by the unwrapped envelope.
      expect(wrapped_rows.size).to eq(1)
    end
  end

  describe 'result object' do
    it 'reports truncation when the feature count reaches the limit' do
      expect(described_class::Result.new(tile: 'x', feature_count: 10, limit: 10)).to be_truncated
      expect(described_class::Result.new(tile: 'x', feature_count: 9, limit: 10)).not_to be_truncated
    end
  end
end
