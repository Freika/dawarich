# frozen_string_literal: true

module Timezones
  class LoadBoundaries
    ASSET_PATH = 'lib/assets/timezones.geojson.gz'
    MAX_VERTICES = 256

    # Subdivided pieces keep each ST_Covers check against a small polygon
    # instead of a whole ocean.
    INSERT_SQL = <<~SQL.freeze
      INSERT INTO timezones (tzid, geom, created_at, updated_at)
      SELECT feature -> 'properties' ->> 'tzid',
             ST_Subdivide(
               ST_CollectionExtract(ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)), 3),
               #{MAX_VERTICES}
             ),
             NOW(), NOW()
      FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
    SQL

    # Without boundaries, timeline times simply stay in the account time zone,
    # so a failed load must stop neither an upgrade nor a boot.
    def self.call_safely(context, path = Rails.root.join(ASSET_PATH))
      new(path).call
      true
    rescue StandardError => e
      Rails.logger.warn(
        "[#{context}] Time zone boundaries were not loaded (#{e.class}: #{e.message}); " \
        'db:seed retries on the next start, or run Timezones::LoadBoundaries.new.call'
      )
      false
    end

    def initialize(path = Rails.root.join(ASSET_PATH))
      @path = path
    end

    def call
      geojson = Zlib::GzipReader.open(@path, &:read)

      Timezone.transaction do
        Timezone.delete_all
        Timezone.connection.execute(Timezone.sanitize_sql_array([INSERT_SQL, geojson]))
      end
      Timezone.connection.execute('ANALYZE timezones')
    end
  end
end
