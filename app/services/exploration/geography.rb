# frozen_string_literal: true

require 'zlib'
require 'digest'

module Exploration
  class Geography
    VERSION = 'natural-earth-5.1.2-collections-20261028-v1'
    METADATA = {
      source: 'Natural Earth 1:10m', release: '5.1.2',
      attribution: 'Natural Earth · public domain',
      url: 'https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-admin-0-countries/',
      detail: 'Natural Earth 1:10m coastline and inland water detail. Small water bodies may be absent.',
      area_method: 'PostGIS geography, WGS84 spheroid', resolution: 9
    }.freeze

    def self.current
      Dataset.find_by(version: VERSION).presence&.then { |d| d if d.completed_at }
    end

    def self.install!
      Dataset.with_advisory_lock('exploration-geography', timeout_seconds: 120) do
        current || new.call
      end || raise('Exploration geography installation is busy')
    end

    def call
      Dataset.transaction do
        dataset = Dataset.create!(version: VERSION, metadata: METADATA)
        connection.execute(<<~SQL)
          CREATE TEMP TABLE exploration_water_import(geom geometry(MultiPolygon,4326)) ON COMMIT DROP
        SQL
        features('lakes').each_slice(100) do |slice|
          values = slice.map { |f| "(#{geometry(f)})" }.join(',')
          connection.execute("INSERT INTO exploration_water_import VALUES #{values}")
        end
        connection.execute('CREATE INDEX ON exploration_water_import USING gist(geom)')
        features('countries').sort_by { |f| f['properties']['ADM0_A3'] }.each do |feature|
          properties = feature['properties']
          code = properties['ADM0_A3'] # Stable dataset identity, including territories without an ISO code.
          name = properties['NAME_EN'].presence || properties['ADMIN'] || properties['NAME']
          connection.execute(<<~SQL)
            INSERT INTO exploration_territories(dataset_id,code,name,boundary,land,land_area)
            WITH boundary AS (SELECT #{geometry(feature)} AS geom), clipped AS (
              SELECT b.geom AS boundary, ST_Multi(ST_CollectionExtract(ST_MakeValid(
                ST_Difference(b.geom, COALESCE((SELECT ST_UnaryUnion(ST_Collect(w.geom))
                  FROM exploration_water_import w WHERE w.geom && b.geom AND ST_Intersects(w.geom,b.geom)),
                  ST_GeomFromText('MULTIPOLYGON EMPTY',4326)))),3)) AS land FROM boundary b
            ) SELECT #{dataset.id},#{q(code)},#{q(name)},boundary,land,ST_Area(land::geography) FROM clipped
          SQL
        end
        Catalog.import!(dataset)
        invalid = Territory.where(dataset_id: dataset.id)
                           .where("NOT ST_IsValid(land) OR land_area <= 0 OR land_area = 'NaN'::float")
        raise 'Invalid exploration land geometry' if invalid.exists?

        dataset.update!(completed_at: Time.current)
        dataset
      end
    end

    private

    def connection = ApplicationRecord.connection
    def q(value) = connection.quote(value)

    def features(name)
      root = Rails.root.join('lib/assets/exploration')
      path = root.join("#{name}.geojson.gz")
      expected = JSON.parse(root.join('checksums.json').read).fetch(name).fetch('sha256')
      raise "Exploration #{name} checksum mismatch" unless Digest::SHA256.file(path).hexdigest == expected

      JSON.parse(Zlib::GzipReader.open(path, &:read)).fetch('features')
    end

    def geometry(feature)
      json = q(feature.fetch('geometry').to_json)
      "ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(#{json}),4326)),3))"
    end
  end
end
