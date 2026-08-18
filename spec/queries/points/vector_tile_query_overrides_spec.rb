# frozen_string_literal: true

require 'rails_helper'

# Anomalies-endpoint parameterization of the shared points tile query. Kept in
# its own file so the original spec remains the untouched regression net for
# the points endpoint.
RSpec.describe Points::VectorTileQuery do
  let(:user) { create(:user) }

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

  describe 'grid_px_override' do
    before do
      # 30m apart: inside one 4px z10 cell (~153m), far beyond a 1px cell (~38m)
      create_point_at(10, 10, anomaly: true)
      create_point_at(40, 10, anomaly: true)
    end

    it 'keeps nearby anomalies separate at 1px where the default grid would merge them' do
      merged = described_class.new(scope: user.points, z: 10, x: 512, y: 511).feature_rows
      separate = described_class.new(scope: user.points, z: 10, x: 512, y: 511,
                                     grid_px_override: 1).feature_rows

      expect(merged.size).to eq(1)
      expect(separate.size).to eq(2)
      expect(separate.map { |r| r['count'].to_i }).to all(eq(1))
    end
  end

  describe 'grid_px_override below the attribute zoom' do
    it 'keeps the benchmarked 4px tier where no popups exist, bounding low-zoom tiles' do
      # 30km apart: BETWEEN a z2 1px cell (~19.6km) and a z2 4px cell (~78km),
      # so this fixture discriminates — the guard keeps them merged (4px tier),
      # while an override honored at z2 would split them into two rows.
      create_point_at(10, 10, anomaly: true)
      create_point_at(30_010, 10, anomaly: true)

      rows = described_class.new(scope: user.points, z: 2, x: 2, y: 1,
                                 grid_px_override: 1).feature_rows

      expect(rows.size).to eq(1)
    end
  end

  describe 'attributes_at_all_zooms' do
    it 'carries per-point attributes below the attribute zoom for sparse scopes' do
      create_point_at(10, 10, anomaly: true, accuracy: 11_000)

      rows = described_class.new(scope: user.points, z: 2, x: 2, y: 1,
                                 attributes_at_all_zooms: true,
                                 extra_property_columns: [:accuracy]).feature_rows

      expect(rows.first['id']).to be_present
      expect(rows.first['accuracy'].to_i).to eq(11_000)
    end
  end

  describe 'extra_property_columns' do
    it 'adds the requested column while the default property set stays EXACTLY the points contract' do
      create_point_at(10, 10, anomaly: true, accuracy: 11_000)

      rows = described_class.new(scope: user.points, z: 10, x: 512, y: 511,
                                 extra_property_columns: [:accuracy]).feature_rows
      default_rows = described_class.new(scope: user.points, z: 10, x: 512, y: 511).feature_rows

      expect(rows.first['accuracy'].to_i).to eq(11_000)
      # Full key-set pin: the shared query serves the live points endpoint —
      # any drift in its default property set is a points regression.
      expect(default_rows.first.keys)
        .to match_array(%w[count id timestamp battery altitude velocity latitude longitude geom])
      expect(rows.first.keys)
        .to match_array(%w[count id timestamp battery altitude velocity latitude longitude accuracy geom])
    end

    it 'rejects columns outside the allowlist and non-integer grid overrides' do
      expect do
        described_class.new(scope: user.points, z: 10, x: 512, y: 511,
                            extra_property_columns: [:raw_data])
      end.to raise_error(ArgumentError)
      expect do
        described_class.new(scope: user.points, z: 10, x: 512, y: 511, grid_px_override: 'DROP')
      end.to raise_error(ArgumentError)
    end
  end
end
