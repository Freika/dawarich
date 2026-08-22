# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::VectorTileQuery do
  let(:user) { create(:user) }

  # 4326 coordinates derived from web-mercator meters so fixtures stay aligned
  # with tile envelopes whatever the constants become.
  def lonlat_at(east, north)
    row = ActiveRecord::Base.connection.select_one(
      "SELECT ST_X(p) AS lon, ST_Y(p) AS lat FROM (
         SELECT ST_Transform(ST_SetSRID(ST_MakePoint(#{east}, #{north}), 3857), 4326) AS p
       ) s"
    )
    [row['lon'].to_f, row['lat'].to_f]
  end

  def linestring_wkt(meter_pairs)
    coords = meter_pairs.map { |east, north| lonlat_at(east, north).join(' ') }.join(', ')
    "LINESTRING(#{coords})"
  end

  def create_track_at(meter_pairs, attrs = {})
    create(:track, user:, original_path: linestring_wkt(meter_pairs), **attrs)
  end

  def feature_rows(z:, x:, y:, scope: user.tracks) # rubocop:disable Naming/MethodParameterName
    described_class.new(scope:, z:, x:, y:).feature_rows
  end

  def npoints(geom)
    ActiveRecord::Base.connection.select_value(
      Track.sanitize_sql_array(['SELECT ST_NPoints(?::geometry)', geom])
    ).to_i
  end

  # z10 tile (512, 511) and z2 tile (2, 1) both have their south-west corner at
  # the web-mercator origin, so offsets in meters are envelope-aligned.
  describe 'feature membership' do
    it 'renders tracks intersecting the tile and omits tracks outside it' do
      inside_a = create_track_at([[10, 10], [2_000, 2_000]])
      inside_b = create_track_at([[5_000, 5_000], [8_000, 8_000]])
      create_track_at([[200_000, 200_000], [210_000, 210_000]])

      rows = feature_rows(z: 10, x: 512, y: 511)

      expect(rows.map { |r| r['id'].to_i }).to contain_exactly(inside_a.id, inside_b.id)
    end
  end

  describe 'simplification' do
    it 'reduces vertices at low zoom while high zoom keeps the shape' do
      # ±2m zigzag over ~200m: below the z8 simplify tolerance (~305m), well
      # above the z14 quantization step (~0.6m/extent unit).
      zigzag = (0..100).map { |i| [10 + (i * 2), 10 + ((i.even? ? 1 : -1) * 2)] }
      create_track_at(zigzag)

      low = feature_rows(z: 8, x: 128, y: 127)
      high = feature_rows(z: 14, x: 8192, y: 8191)

      expect(low.size).to eq(1)
      expect(high.size).to eq(1)
      expect(npoints(low.first['geom'])).to be < npoints(high.first['geom'])
    end
  end

  describe 'time-range scope composition' do
    it 'excludes tracks outside the window and keeps boundary-spanning ones through the full SQL' do
      old = create_track_at([[10, 10], [500, 500]],
                            start_at: 10.days.ago, end_at: 9.days.ago)
      spanning = create_track_at([[600, 600], [900, 900]],
                                 start_at: 2.days.ago, end_at: 1.hour.ago)

      range_start = 1.day.ago
      range_end = Time.zone.now
      scope = user.tracks.where('end_at >= ? AND start_at <= ?', range_start, range_end)
      rows = feature_rows(z: 10, x: 512, y: 511, scope: scope)

      expect(rows.map { |r| r['id'].to_i }).to eq([spanning.id])
      expect(rows.map { |r| r['id'].to_i }).not_to include(old.id)
    end
  end

  describe 'coordinate validation and timeout' do
    it 'raises on invalid tile coordinates' do
      expect { described_class.new(scope: user.tracks, z: -1, x: 0, y: 0).call }
        .to raise_error(Tracks::VectorTileQuery::InvalidTileCoordinatesError)
      expect { described_class.new(scope: user.tracks, z: 2, x: 4, y: 0).call }
        .to raise_error(Tracks::VectorTileQuery::InvalidTileCoordinatesError)
      expect { described_class.new(scope: user.tracks, z: 'abc', x: 0, y: 0).call }
        .to raise_error(Tracks::VectorTileQuery::InvalidTileCoordinatesError)
    end

    it 'cancels queries exceeding the statement timeout' do
      create_track_at([[10, 10], [500, 500]])
      allow(VectorTileTimeout).to receive(:query_timeout_ms).and_return(50)

      slow_scope = user.tracks.where('(SELECT pg_sleep(0.3)) IS NOT NULL')

      expect do
        described_class.new(scope: slow_scope, z: 10, x: 512, y: 511).call
      end.to raise_error(ActiveRecord::QueryCanceled)
    end
  end

  describe 'geometry fidelity' do
    it 'returns MVT-space vertex coordinates matching the transform math' do
      tile_span = Tracks::VectorTileQuery::WEB_MERCATOR_WORLD / 4
      create_track_at([[tile_span * 0.25, tile_span * 0.25], [tile_span * 0.5, tile_span * 0.5]])

      rows = feature_rows(z: 2, x: 2, y: 1)
      coords = ActiveRecord::Base.connection.select_one(
        Track.sanitize_sql_array(
          ['SELECT ST_X(ST_PointN(?::geometry, 2)) AS x, ST_Y(ST_PointN(?::geometry, 2)) AS y',
           rows.first['geom'], rows.first['geom']]
        )
      )

      # Midpoint of the tile → extent midpoint; MVT y counts from the tile's north edge.
      expect(coords['x'].to_f).to be_within(2).of(2048)
      expect(coords['y'].to_f).to be_within(2).of(2048)
    end

    it 'pins classic parity for a seam-crossing track: the raw planar line spans the world band' do
      create(:track, user:, original_path: 'LINESTRING(139.7 35.7, -118.2 34.05)')

      rows = feature_rows(z: 2, x: 2, y: 1)

      # The planar line from Tokyo to LA crosses the central-Europe tile —
      # exactly what classic GeoJSON rendering draws today. Documented artifact.
      expect(rows.size).to eq(1)

      # Vertex VALUES, not mere presence: a future wrapped-branch attempt that
      # translated the geometry would change these coordinates without changing
      # the count. The clipped segment must run west-to-east across the whole
      # tile at a roughly constant MVT y (the planar chord is near-horizontal).
      coords = ActiveRecord::Base.connection.select_one(
        Track.sanitize_sql_array(
          ['SELECT ST_XMin(?::geometry) AS xmin, ST_XMax(?::geometry) AS xmax,
                   ST_YMin(?::geometry) AS ymin, ST_YMax(?::geometry) AS ymax',
           rows.first['geom'], rows.first['geom'], rows.first['geom'], rows.first['geom']]
        )
      )
      expect(coords['xmin'].to_f).to be <= 0
      expect(coords['xmax'].to_f).to be >= 4096
      expect(coords['ymin'].to_f).to be_between(0, 4096)
    end
  end

  describe 'tile properties' do
    it 'matches the GeoJSON serializer scalar property set with iso8601 timestamps' do
      create_track_at([[10, 10], [500, 500]], dominant_mode: :driving)

      row = feature_rows(z: 10, x: 512, y: 511).first
      # Derived from the serializer, not hardcoded: tiles must track its scalar
      # contract so JS click/popup/animation flows stay source-agnostic. Array
      # properties (mode_timeline, segments) cannot ride MVT — excluded.
      serialized = Tracks::GeojsonSerializer.new(user.tracks.first).call
      serializer_scalar_keys =
        serialized[:features].first[:properties].keys.map(&:to_s) -
        %w[mode_timeline segments]

      expect(row.keys).to match_array(serializer_scalar_keys + ['geom'])
      expect(row['start_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(row['color']).to eq(Tracks::GeojsonSerializer::DEFAULT_COLOR)
      expect(row['dominant_mode']).to eq('driving')
      expect(row['dominant_mode_emoji']).to eq('🚗')
    end
  end

  describe 'result envelope' do
    it 'reports feature_count and an unreachable limit' do
      create_track_at([[10, 10], [500, 500]])

      result = described_class.new(scope: user.tracks, z: 10, x: 512, y: 511).call

      expect(result.feature_count).to eq(1)
      expect(result.limit).to eq(Tracks::VectorTileQuery::TRACKS_PER_TILE_LIMIT)
      expect(result.truncated?).to be(false)
      expect(result.tile).to be_present
    end
  end
end
