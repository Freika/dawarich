# frozen_string_literal: true

# Display-only geometry. Never used to calculate eligibility or exploration area.
# bundle exec rails runner script/export_achievement_globe_land.rb tmp/achievement-globe-land.geojson
raise 'Provide an output filename' unless ARGV.one?

dataset = Exploration::Geography.current || raise('Install the bundled exploration geography first')
geometry = ApplicationRecord.connection.select_value(<<~SQL)
  WITH world AS (
    SELECT ST_UnaryUnion(ST_Collect(land ORDER BY code)) AS geom
    FROM exploration_territories WHERE dataset_id=#{dataset.id} AND kind='country'
  ), pieces AS (SELECT (ST_Dump(geom)).geom FROM world)
  SELECT ST_AsGeoJSON(ST_Multi(ST_Collect(ST_SimplifyPreserveTopology(geom,0.18))),5)
  FROM pieces WHERE ST_Area(geom::geography) >= 500000000
SQL
File.write(ARGV.first, { type: 'Feature', properties: { source: 'Natural Earth',
                                                       release: dataset.metadata.fetch('release'),
                                                       simplification_degrees: 0.18, minimum_island_km2: 500 },
                         geometry: JSON.parse(geometry) }.to_json)
puts 'Exported display-only globe land'
