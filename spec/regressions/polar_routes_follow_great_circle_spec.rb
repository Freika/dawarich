# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Polar routes follow the great circle' do
  it 'renders a sparse polar track through its spherical midpoint instead of along a latitude parallel' do
    track = create(:track, original_path: 'LINESTRING(40 82, 140 82)', dominant_mode: :flying)
    rows = Tracks::VectorTileQuery.new(scope: Track.where(id: track.id), z: 0, x: 0, y: 0).feature_rows
    expect(rows.map { |row| row['id'].to_i }).to eq([track.id])

    radians = Math::PI / 180
    midpoint_longitude = 90.0
    midpoint_latitude = Math.atan(Math.tan(82 * radians) / Math.cos(50 * radians))
    midpoint_x = (midpoint_longitude + 180) / 360 * Tracks::VectorTileQuery::EXTENT
    midpoint_y = (1 - Math.log(Math.tan(Math::PI / 4 + midpoint_latitude / 2)) / Math::PI) / 2 *
                 Tracks::VectorTileQuery::EXTENT
    distance_sql = Track.sanitize_sql_array(
      ['SELECT ST_Distance(?::geometry, ST_SetSRID(ST_MakePoint(?, ?), 3857))',
       rows.first.fetch('geom'), midpoint_x, midpoint_y]
    )
    midpoint_error = ActiveRecord::Base.connection.select_value(distance_sql).to_f

    expect(midpoint_error).to be < 10,
                              "Polar route misses its great-circle midpoint by #{midpoint_error.round(2)} tile units"
  end
end
