# frozen_string_literal: true

module Exploration
  # Union land before measuring it: disputed/overlapping territories must not
  # count twice. Both totals are prepared by the worker, never on map requests.
  class WorldTotals
    def self.prepare_dataset!(dataset)
      return if dataset.world_land_area

      dataset.with_lock do
        next if dataset.world_land_area

        area = ApplicationRecord.connection.select_value(<<~SQL)
          SELECT COALESCE(ST_Area(ST_UnaryUnion(ST_Collect(land))::geography),0)
          FROM exploration_territories WHERE dataset_id=#{dataset.id} AND kind='country'
        SQL
        dataset.update!(world_land_area: area)
      end
    end

    def self.opened_area(snapshot)
      ApplicationRecord.connection.select_value(<<~SQL).to_f
        SELECT COALESCE(SUM(ST_Area(clipped.land::geography)),0)
        FROM exploration_openings o JOIN exploration_cells c ON c.id=o.cell_id
        CROSS JOIN LATERAL (
          SELECT ST_UnaryUnion(ST_Collect(ST_CollectionExtract(ST_Intersection(c.geom,t.land),3))) AS land
          FROM exploration_territories t WHERE t.dataset_id=#{snapshot.dataset_id} AND t.kind='country'
            AND t.land && c.geom AND ST_Intersects(t.land,c.geom)
        ) clipped WHERE o.snapshot_id=#{snapshot.id}
      SQL
    end
  end
end
