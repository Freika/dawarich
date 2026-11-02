# frozen_string_literal: true

module Exploration
  class Result
    def initialize(user, start_at: nil, end_at: nil)
      @user = user
      @start_at = start_at
      @end_at = end_at
    end

    def call
      state = Schedule.call(@user)
      snapshot = Snapshot.find_by(id: state.snapshot_id, user_id: @user.id)
      updating = !state.settled?(snapshot)
      status = if state.failed_at && updating
                 'error'
               elsif updating
                 snapshot ? 'updating' : 'calculating'
               else
                 'ready'
               end
      return { status: status, snapshot_id: nil, countries: [], resolution: 9 } unless snapshot

      dataset = Dataset.find(snapshot.dataset_id)
      countries = totals(snapshot)
      opened_area = countries.sum { |c| c[:opened_area] }
      world_land_area = dataset.world_land_area
      {
        status: status, snapshot_id: snapshot.id, updated_at: snapshot.completed_at.iso8601,
        resolution: 9, dataset: dataset.metadata.merge(version: dataset.version),
        cells_count: Opening.where(snapshot_id: snapshot.id).count,
        opened_area: opened_area,
        world: { land_area: world_land_area, opened_area: snapshot.world_opened_area,
                 percentage: world_percentage(snapshot.world_opened_area, world_land_area) },
        new_area: countries.sum { |c| c[:new_area] },
        countries: countries
      }
    end

    private

    def world_percentage(opened_area, land_area)
      return unless opened_area && land_area&.positive?

      opened_area * 100.0 / land_area
    end

    def totals(snapshot)
      new_areas = newly_opened(snapshot)
      sql = ApplicationRecord.sanitize_sql_array([<<~SQL, { snapshot: snapshot.id }])
        SELECT t.id,t.code,t.name,t.land_area,r.opened_area,r.visited,
          ST_XMin(Box3D(t.boundary)) AS west,ST_YMin(Box3D(t.boundary)) AS south,
          ST_XMax(Box3D(t.boundary)) AS east,ST_YMax(Box3D(t.boundary)) AS north
        FROM exploration_country_totals r JOIN exploration_territories t ON t.id=r.territory_id
        WHERE r.snapshot_id=:snapshot AND t.kind='country' ORDER BY r.opened_area DESC,t.name
      SQL
      ApplicationRecord.connection.select_all(sql).map do |r|
        {
          id: r['id'], code: r['code'], name: r['name'], land_area: r['land_area'],
          opened_area: r['opened_area'], percentage: r['opened_area'] * 100.0 / r['land_area'],
          new_area: new_areas.fetch(r['id'].to_s, 0), visited: r['visited'],
          bounds: [[r['west'], r['south']], [r['east'], r['north']]]
        }
      end
    end

    def newly_opened(snapshot)
      return {} unless @start_at && @end_at

      params = { snapshot: snapshot.id, dataset: snapshot.dataset_id, start: @start_at, end: @end_at }
      sql = ApplicationRecord.sanitize_sql_array([<<~SQL, params])
        SELECT a.key,SUM(a.value::float) AS area FROM exploration_openings o
        JOIN exploration_cell_coverages c ON c.cell_id=o.cell_id AND c.dataset_id=:dataset
        CROSS JOIN LATERAL jsonb_each_text(c.areas) a
        WHERE o.snapshot_id=:snapshot AND o.first_timestamp BETWEEN :start AND :end GROUP BY a.key
      SQL
      ApplicationRecord.connection.select_all(sql).to_h { |r| [r['key'], r['area']] }
    end
  end
end
