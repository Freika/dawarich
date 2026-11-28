# frozen_string_literal: true

module Achievements
  class LoadDisputedAreas
    ASSET_PATH = 'lib/assets/disputed_areas.geojson'
    MAX_VERTICES = 256

    INSERT_SQL = <<~SQL.freeze
      INSERT INTO disputed_areas (name, geom, created_at, updated_at)
      SELECT feature -> 'properties' ->> 'name',
             ST_Subdivide(
               ST_CollectionExtract(ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)), 3),
               #{MAX_VERTICES}
             ),
             NOW(), NOW()
      FROM jsonb_array_elements(?::jsonb -> 'features') AS feature
    SQL

    def call
      geojson = File.read(Rails.root.join(ASSET_PATH))

      DisputedArea.transaction do
        DisputedArea.delete_all
        DisputedArea.connection.execute(DisputedArea.sanitize_sql_array([INSERT_SQL, geojson]))
      end
      # The recalculation enqueued next must not plan against an unanalyzed table.
      DisputedArea.connection.execute('ANALYZE disputed_areas')
    end
  end
end
