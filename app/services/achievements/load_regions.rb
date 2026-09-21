# frozen_string_literal: true

module Achievements
  class LoadRegions
    class MissingCountriesError < StandardError; end

    ASSET_PATH = 'lib/assets/admin1_world.geojson'
    CODE_PROPERTY = 'iso_3166_2'
    MISSING_COUNTRIES = 'countries table is empty: run db/seeds.rb before loading achievement ' \
                        'regions, country-level achievements resolve through Country#iso_a2'

    UPSERT_SQL = <<~SQL.freeze
      INSERT INTO regions (code, geom, created_at, updated_at)
      SELECT feature -> 'properties' ->> '#{CODE_PROPERTY}',
             ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)),
             NOW(), NOW()
      FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
      ON CONFLICT (code) DO UPDATE SET geom = EXCLUDED.geom, updated_at = EXCLUDED.updated_at
    SQL

    REPAIR_SQL = <<~SQL
      UPDATE regions
      SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
      WHERE NOT ST_IsValid(geom)
    SQL

    def call
      raise MissingCountriesError, MISSING_COUNTRIES if Country.none?

      geojson = File.read(Rails.root.join(ASSET_PATH))
      Region.connection.execute(Region.sanitize_sql_array([UPSERT_SQL, geojson]))
      Region.connection.execute(REPAIR_SQL)
    end
  end
end
