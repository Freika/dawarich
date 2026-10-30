# frozen_string_literal: true

module Exploration
  class Coverage
    def self.ensure!(ids, dataset)
      connection = ApplicationRecord.connection
      q = ->(v) { connection.quote(v) }
      missing = ids - Cell.where(id: ids).pluck(:id)
      if missing.any?
        values = missing.map do |id|
          json = CellGeometry.geojson(id).to_json
          geometry = "ST_SetSRID(ST_GeomFromGeoJSON(#{q.call(json)}),4326)"
          "(#{q.call(id)},ST_Multi(ST_CollectionExtract(ST_WrapX(ST_WrapX(#{geometry},180,-360),-180,360),3)))"
        end
        connection.execute("INSERT INTO exploration_cells(id,geom) VALUES #{values.join(',')} ON CONFLICT DO NOTHING")
      end
      connection.execute(<<~SQL)
        INSERT INTO exploration_cell_coverages(dataset_id,cell_id,areas)
        SELECT #{dataset.id}, c.id, COALESCE((SELECT jsonb_object_agg(clipped.id,clipped.area) FROM (
          SELECT t.id, ST_Area(ST_CollectionExtract(ST_Intersection(c.geom,t.land),3)::geography) AS area
          FROM exploration_territories t WHERE t.dataset_id=#{dataset.id} AND t.land && c.geom
            AND ST_Intersects(t.land,c.geom)
        ) clipped WHERE clipped.area > 0), '{}'::jsonb)
        FROM exploration_cells c WHERE c.id IN (#{ids.map(&q).join(',')})
          AND NOT EXISTS (SELECT 1 FROM exploration_cell_coverages v WHERE v.cell_id=c.id AND v.dataset_id=#{dataset.id})
        ON CONFLICT DO NOTHING
      SQL
    end
  end
end
