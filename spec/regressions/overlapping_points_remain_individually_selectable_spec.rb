# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Overlapping map points remain individually selectable' do
  it 'exposes each point identity with count one at maximum zoom for individual editing and deletion' do
    user = create(:user)
    # Made-up coordinates in the open South Pacific. These are separate
    # recordings at the same location, not duplicate (location, time) records.
    longitude = -130.123456
    latitude = -55.123456
    points = 3.times.map do |index|
      create(:point, user: user, longitude: longitude, latitude: latitude,
                     timestamp: 1_720_000_000 + (index * 60))
    end

    zoom = 22
    tile_count = 1 << zoom
    tile_x = ((longitude + 180) / 360 * tile_count).floor
    lat_radians = latitude * Math::PI / 180
    tile_y = ((1 - Math.asinh(Math.tan(lat_radians)) / Math::PI) / 2 * tile_count).floor
    query = Points::VectorTileQuery.new(scope: user.points, z: zoom, x: tile_x, y: tile_y)

    # These are the actual SQL features encoded into the map's MVT response.
    # The UI permits a popup, drag and individual delete only when count <= 1.
    rows = query.feature_rows

    aggregate_failures do
      expect(rows.pluck('id')).to match_array(points.map(&:id))
      expect(rows.pluck('count')).to all(eq(1))
      expect(query.call.feature_count).to eq(points.size)
    end
  end
end
