# frozen_string_literal: true

require 'rails_helper'

# Guards the US subdivision polygons in lib/assets/admin1_world.geojson.
#
# An earlier revision of this asset was simplified hard enough to tear holes in
# complex coastlines -- New York City, New Orleans and the Outer Banks fell
# outside every subdivision -- while also claiming open Great Lakes water for
# the states around them. Both directions are pinned here.
#
# Fixtures are derived from the Census source, not hand-picked: the interior
# points are each subdivision's maximum-inscribed-circle centre, and the
# coastal points sit inside the largest piece of land the old asset omitted.
RSpec.describe 'bundled US subdivision geometry' do
  # [iso_3166_2, longitude, latitude]
  let(:deepest_interior) do
    [
      ['US-AK', -154.7861, 65.3326],
      ['US-AL', -86.7699, 32.6017],
      ['US-AR', -92.6592, 34.7568],
      ['US-AZ', -111.5927, 34.4162],
      ['US-CA', -121.9153, 40.0774],
      ['US-CO', -106.7058, 38.9945],
      ['US-CT', -73.1184, 41.6414],
      ['US-DC', -76.9936, 38.8930],
      ['US-DE', -75.4574, 38.7080],
      ['US-FL', -81.4348, 27.6794],
      ['US-GA', -83.2274, 32.2933],
      ['US-HI', -155.5190, 19.6354],
      ['US-IA', -94.5031, 42.0368],
      ['US-ID', -115.1123, 43.8133],
      ['US-IL', -89.2310, 40.3046],
      ['US-IN', -86.1666, 40.2979],
      ['US-KS', -98.3289, 38.5006],
      ['US-KY', -84.4757, 37.7183],
      ['US-LA', -92.6218, 31.8799],
      ['US-MA', -72.9680, 42.3891],
      ['US-MD', -76.9454, 39.3527],
      ['US-ME', -69.0388, 45.7221],
      ['US-MI', -84.9657, 43.0093],
      ['US-MN', -94.6259, 46.6801],
      ['US-MO', -92.7138, 38.3927],
      ['US-MS', -89.6764, 33.3601],
      ['US-MT', -112.0909, 46.8615],
      ['US-NC', -78.3899, 35.3234],
      ['US-ND', -98.5269, 47.4715],
      ['US-NE', -100.0275, 41.5012],
      ['US-NH', -71.6591, 43.3784],
      ['US-NJ', -74.6068, 40.8225],
      ['US-NM', -106.5458, 34.4970],
      ['US-NV', -116.5069, 39.5377],
      ['US-NY', -74.8134, 43.3041],
      ['US-OH', -83.4129, 40.0936],
      ['US-OK', -96.2221, 35.4262],
      ['US-OR', -119.1618, 43.9593],
      ['US-PA', -76.8901, 40.8610],
      ['US-PR', -66.8998, 18.2289],
      ['US-RI', -71.5969, 41.8173],
      ['US-SC', -80.5915, 33.6899],
      ['US-SD', -97.9661, 44.4172],
      ['US-TN', -86.3932, 35.8221],
      ['US-TX', -98.3899, 30.9574],
      ['US-UT', -111.9459, 39.1009],
      ['US-VA', -78.3019, 37.7275],
      ['US-VT', -72.6904, 44.2362],
      ['US-WA', -120.4794, 47.3726],
      ['US-WI', -89.7369, 44.5338],
      ['US-WV', -80.9156, 38.4704],
      ['US-WY', -107.5534, 43.0003],
    ]
  end

  # Land the previous revision dropped; each point is inside its subdivision.
  let(:previously_omitted) do
    [
      ['US-LA', -90.0739, 30.2063], # 1827 km2
      ['US-FL', -85.9755, 30.2631], # 1193 km2
      ['US-AK', -163.9252, 60.7990], # 1097 km2
      ['US-TX', -96.3168, 28.5343], # 1095 km2
      ['US-VA', -75.7465, 37.4719], # 675 km2
      ['US-MT', -116.0488, 48.2909], # 648 km2
      ['US-NY', -73.1247, 40.6965], # 479 km2
      ['US-NJ', -74.1854, 39.6608], # 476 km2
      ['US-GA', -81.2243, 31.5006], # 411 km2
      ['US-WA', -117.0351, 48.7034], # 342 km2
      ['US-UT', -114.0449, 39.0973], # 337 km2
      ['US-ND', -104.0478, 48.6991], # 336 km2
      ['US-MD', -75.1675, 38.2340], # 290 km2
      ['US-MS', -88.4677, 31.6636], # 249 km2
      ['US-NC', -75.7510, 36.1685], # 248 km2
      ['US-ID', -117.0224, 42.9764], # 217 km2
      ['US-NM', -103.0466, 34.8749], # 191 km2
      ['US-OR', -119.0081, 41.9960], # 188 km2
      ['US-KY', -87.7132, 36.6390], # 187 km2
      ['US-CO', -105.4491, 36.9961], # 187 km2
      ['US-CA', -116.0422, 36.1097], # 186 km2
      ['US-AL', -88.2141, 33.9776], # 162 km2
      ['US-MA', -70.0317, 41.9495], # 161 km2
      ['US-SD', -98.3637, 42.9204], # 155 km2
      ['US-IA', -95.4315, 40.5851], # 137 km2
      ['US-WI', -91.3364, 43.9300], # 130 km2
      ['US-ME', -69.6123, 43.8633], # 128 km2
      ['US-RI', -71.2693, 41.5622], # 119 km2
      ['US-TN', -90.2908, 35.0163], # 114 km2
      ['US-KS', -94.6153, 38.2231], # 114 km2
      ['US-MN', -94.7495, 49.0496], # 114 km2
      ['US-AR', -91.1448, 33.0431], # 98 km2
      ['US-MO', -91.0520, 36.4986], # 96 km2
      ['US-AZ', -114.3869, 34.5515], # 96 km2
      ['US-VT', -72.1636, 43.8994], # 96 km2
      ['US-OK', -99.7839, 34.4650], # 85 km2
      ['US-NV', -118.0012, 37.5923], # 84 km2
      ['US-IL', -88.0425, 38.0483], # 67 km2
      ['US-HI', -156.9914, 20.8350], # 66 km2
      ['US-IN', -84.8116, 40.0449], # 65 km2
      ['US-PR', -67.8919, 18.0880], # 55 km2
      ['US-SC', -80.5209, 32.4945], # 54 km2
      ['US-WY', -110.4885, 40.9975], # 52 km2
      ['US-CT', -71.7939, 41.7250], # 51 km2
      ['US-NH', -71.8869, 42.7130], # 50 km2
      ['US-PA', -75.2435, 39.8691], # 49 km2
      ['US-MI', -89.5854, 46.2359], # 46 km2
      ['US-DE', -75.0896, 38.5989], # 40 km2
    ]
  end

  # Open lake water the previous revision claimed; no subdivision may cover it.
  let(:open_lake_water) do
    [
      ['US-MI', -82.9230, 44.0806], # 57171 km2
      ['US-WI', -87.3768, 43.9729], # 18948 km2
      ['US-OH', -81.5263, 41.8515], # 9277 km2
      ['US-NY', -76.4760, 43.7066], # 8929 km2
      ['US-MN', -90.5405, 47.3622], # 6630 km2
      ['US-IL', -87.5236, 41.5778], # 4097 km2
      ['US-PA', -80.5194, 41.2377], # 2044 km2
      ['US-IN', -87.2056, 41.6896], # 600 km2
    ]
  end

  let(:subdivisions) { Rails.root.join('lib/assets/admin1_world.geojson').read }

  # One round trip: the asset is parsed once and every fixture tested against it.
  def misses(fixtures)
    sql = <<~SQL
      WITH us AS (
        SELECT feature -> 'properties' ->> 'iso_3166_2' AS code,
               ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326) AS geom
        FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
        WHERE feature -> 'properties' ->> 'iso_3166_2' LIKE 'US-%'
      ),
      expected AS (
        SELECT (value ->> 0) AS code,
               (value ->> 1)::float AS lon,
               (value ->> 2)::float AS lat
        FROM jsonb_array_elements(?::jsonb) AS value
      )
      SELECT e.code
      FROM expected e
      WHERE NOT EXISTS (
        SELECT 1 FROM us
        WHERE us.code = e.code
          AND ST_Covers(us.geom, ST_SetSRID(ST_MakePoint(e.lon, e.lat), 4326))
      )
      ORDER BY e.code
    SQL

    query = ActiveRecord::Base.sanitize_sql_array([sql, subdivisions, fixtures.to_json])
    ActiveRecord::Base.connection.select_values(query)
  end

  def covers(fixtures)
    sql = <<~SQL
      WITH us AS (
        SELECT feature -> 'properties' ->> 'iso_3166_2' AS code,
               ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326) AS geom
        FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
        WHERE feature -> 'properties' ->> 'iso_3166_2' LIKE 'US-%'
      ),
      expected AS (
        SELECT (value ->> 0) AS code,
               (value ->> 1)::float AS lon,
               (value ->> 2)::float AS lat
        FROM jsonb_array_elements(?::jsonb) AS value
      )
      SELECT e.code
      FROM expected e
      JOIN us ON us.code = e.code
      WHERE ST_Covers(us.geom, ST_SetSRID(ST_MakePoint(e.lon, e.lat), 4326))
      ORDER BY e.code
    SQL

    query = ActiveRecord::Base.sanitize_sql_array([sql, subdivisions, fixtures.to_json])
    ActiveRecord::Base.connection.select_values(query)
  end

  it 'ships exactly one polygon per US subdivision' do
    shipped = Oj.load(subdivisions)['features']
                .map { |feature| feature['properties']['iso_3166_2'] }
                .select { |code| code.start_with?('US-') }

    expect(shipped.size).to eq(52)
    expect(shipped.uniq.size).to eq(shipped.size)
  end

  it 'covers the deepest interior point of every US subdivision' do
    expect(misses(deepest_interior)).to be_empty
  end

  it 'covers the coastal and island land earlier revisions dropped' do
    expect(misses(previously_omitted)).to be_empty
  end

  it 'leaves open Great Lakes water outside every subdivision' do
    expect(covers(open_lake_water)).to be_empty
  end
end
