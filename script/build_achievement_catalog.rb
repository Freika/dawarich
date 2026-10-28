# frozen_string_literal: true

require 'json'
require 'zlib'
require 'digest'
require 'fileutils'

# Run with: bundle exec rails runner script/build_achievement_catalog.rb tmp/catalog/*.osm.json
# Input files are saved, public Overpass responses. No request runs here.
raise 'Provide one or more saved Overpass JSON files' if ARGV.empty?

connection = ApplicationRecord.connection
sources = ARGV.map { |path| JSON.parse(File.read(path)) }
records = sources.flat_map { |source| source.fetch('elements') }
manifest = JSON.parse(File.read('lib/assets/achievement_collections/manifest.json'))
selected = manifest.fetch('features')
raise 'Duplicate catalog identity' unless selected.pluck('code').uniq.size == selected.size

features = selected.map do |entry|
  id, kind = entry.values_at('osm_id', 'kind')
  relation = records.find { |record| record['id'] == id } or raise "Missing relation #{id}"
  lines = relation.fetch('members').filter_map do |member|
    next unless member['type'] == 'way' && %w[outer inner].include?(member['role'])
    raise "Incomplete relation #{id}, way #{member['ref']}" unless member['geometry']&.size.to_i > 1

    { type: 'LineString', coordinates: member['geometry'].map { |point| [point.fetch('lon'), point.fetch('lat')] } }
  end
  input = { type: 'GeometryCollection', geometries: lines }
  result = connection.select_one(ApplicationRecord.sanitize_sql_array([<<~SQL, JSON.generate(input)]))
    WITH source AS (SELECT ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_BuildArea(
      ST_UnaryUnion(ST_SetSRID(ST_GeomFromGeoJSON(?),4326)))),3)) AS g)
    SELECT ST_AsGeoJSON(g,7) AS geometry, ST_IsValid(g) AS valid,
           ST_Area(g::geography)/1000000 AS area,
           ST_X(ST_PointOnSurface(g)) AS longitude,ST_Y(ST_PointOnSurface(g)) AS latitude FROM source
  SQL
  raise "Invalid relation #{id}" unless result['valid'] == true && result['area'].to_f.positive?

  tags = relation.fetch('tags')
  puts "#{kind} #{tags.fetch('name')}: #{result['area']} km2 at #{result['latitude']},#{result['longitude']}"
  { type: 'Feature', properties: { code: entry.fetch('code'), kind: kind,
      name: tags['name:en'] || tags.fetch('name'), local_name: tags.fetch('name'),
      source: 'OpenStreetMap', osm_type: 'relation', osm_id: id,
      osm_version: relation['version'], osm_timestamp: relation['timestamp'],
      boundary: tags['boundary'], admin_level: tags['admin_level'],
      protection_title: tags['protection_title'], protect_class: tags['protect_class'],
      website: tags['website'], timezone: entry.fetch('timezone'),
      source_url: "https://www.openstreetmap.org/relation/#{id}" }, geometry: JSON.parse(result.fetch('geometry')) }
end
output = { type: 'FeatureCollection', version: manifest.fetch('version'),
           attribution: '© OpenStreetMap contributors · ODbL 1.0',
           timestamp_osm_base: sources.map { |source| source.dig('osm3s', 'timestamp_osm_base') }.max,
           features: features }
directory = 'lib/assets/achievement_collections'
FileUtils.mkdir_p(directory)
path = "#{directory}/germany.geojson.gz"
Zlib::GzipWriter.open(path) do |writer|
  writer.mtime = 0
  writer.write(JSON.generate(output))
end
File.write("#{directory}/checksums.json",
           "#{JSON.pretty_generate({ 'germany.geojson.gz' => Digest::SHA256.file(path).hexdigest })}\n")
puts 'Pinned catalog written'
