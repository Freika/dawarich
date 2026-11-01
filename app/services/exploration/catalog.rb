# frozen_string_literal: true

require 'zlib'
require 'digest'

module Exploration
  class Catalog
    ROOT = 'lib/assets/achievement_collections'
    # One file per region, each with its own version, so a region can be added or refreshed on its own.
    SOURCES = {
      'germany.geojson.gz' => 'germany-pilot-20261028-v1',
      'bulgaria.geojson.gz' => 'bulgaria-20261101-v1'
    }.freeze

    def self.import!(dataset)
      root = Rails.root.join(ROOT)
      checksums = JSON.parse(root.join('checksums.json').read)
      SOURCES.each do |file, version|
        path = root.join(file)
        expected = checksums.fetch(file)
        raise 'Achievement catalog checksum mismatch' unless Digest::SHA256.file(path).hexdigest == expected

        json = JSON.parse(Zlib::GzipReader.open(path, &:read))
        raise 'Achievement catalog version mismatch' unless json.fetch('version') == version

        json.fetch('features').each { |feature| insert(dataset, feature, version, json['attribution']) }
      end
    end

    def self.insert(dataset, feature, version, attribution)
      properties = feature.fetch('properties')
      raise 'Unsupported catalog kind' unless %w[city park].include?(properties['kind'])

      connection = ApplicationRecord.connection
      quote = ->(value) { connection.quote(value) }
      connection.execute(<<~SQL)
        INSERT INTO exploration_territories(dataset_id,code,name,kind,timezone,source_metadata,boundary,land,land_area)
        WITH boundary AS (SELECT ST_Multi(ST_CollectionExtract(ST_MakeValid(
          ST_SetSRID(ST_GeomFromGeoJSON(#{quote.call(feature.fetch('geometry').to_json)}),4326)),3)) AS geom),
        clipped AS (
          SELECT geom AS boundary, ST_Multi(ST_CollectionExtract(ST_Intersection(geom,COALESCE(
            (SELECT ST_UnaryUnion(ST_Collect(t.land)) FROM exploration_territories t
             WHERE t.dataset_id=#{dataset.id} AND t.kind='country' AND t.land && geom AND ST_Intersects(t.land,geom)),
            ST_GeomFromText('MULTIPOLYGON EMPTY',4326))),3)) AS land FROM boundary
        ) SELECT #{dataset.id},#{quote.call(properties.fetch('code'))},#{quote.call(properties.fetch('name'))},
                 #{quote.call(properties.fetch('kind'))},#{quote.call(properties.fetch('timezone'))},
                 #{quote.call(properties.merge('catalog_version' => version, 'attribution' => attribution).to_json)},
                 boundary,land,ST_Area(land::geography) FROM clipped
        ON CONFLICT(dataset_id,code) DO NOTHING
      SQL
    end
    private_class_method :insert
  end
end
