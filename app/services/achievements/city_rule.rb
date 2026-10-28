# frozen_string_literal: true

module Achievements
  class CityRule
    THRESHOLDS = [1, 5, 10, 25].freeze

    def self.call(user, selection, snapshot, privacy_zone_masker: nil)
      raise ArgumentError, 'Snapshot belongs to another user' unless snapshot.user_id == user.id

      territory = Exploration::Territory.find_by(dataset_id: snapshot.dataset_id,
                                                 code: selection.territory_code, kind: 'city')
      return unless territory

      privacy = privacy_zone_masker&.any? ? "AND NOT #{privacy_zone_masker.touches_sql('cells.geom')}" : ''
      rows = ApplicationRecord.connection.select_rows(<<~SQL)
        SELECT o.first_timestamp,(c.areas->>'#{territory.id}')::float AS area,o.point_id
        FROM exploration_openings o JOIN exploration_cell_coverages c
          ON c.cell_id=o.cell_id AND c.dataset_id=#{snapshot.dataset_id}
        JOIN exploration_cells cells ON cells.id=o.cell_id
        WHERE o.snapshot_id=#{snapshot.id} AND (c.areas->>'#{territory.id}')::float > 0
        #{privacy}
        ORDER BY o.first_timestamp,o.point_id
      SQL
      area = 0.0
      levels = {}
      evidence = {}
      rows.each do |timestamp, contribution, point_id|
        area += contribution
        THRESHOLDS.each_with_index do |threshold, index|
          next unless area * 100 / territory.land_area >= threshold

          key = (index + 1).to_s
          next if levels.key?(key)

          levels[key] = Time.at(timestamp).utc.iso8601
          evidence[key] = { 'point_id' => point_id, 'opened_area' => area, 'at' => levels[key] }
        end
      end
      center = territory_center(territory)
      { series: 'city', subject_key: selection.territory_code, city_selection_id: selection.id, selection_id: nil,
        data: { 'status' => 'ready', 'name' => territory.name, 'timezone' => territory.timezone,
                'latitude' => center[1], 'longitude' => center[0], 'progress' => area * 100 / territory.land_area,
                'target' => 100, 'opened_area' => area, 'land_area' => territory.land_area,
                'levels' => levels, 'snapshot_id' => snapshot.id, 'dataset_id' => snapshot.dataset_id,
                'territory_id' => territory.id, 'territory_code' => territory.code,
                'source' => territory.source_metadata, 'evidence' => [], 'level_evidence' => evidence } }
    end

    def self.territory_center(territory)
      ApplicationRecord.connection.select_rows(<<~SQL).first
        SELECT ST_X(ST_PointOnSurface(boundary)),ST_Y(ST_PointOnSurface(boundary))
        FROM exploration_territories WHERE id=#{territory.id}
      SQL
    end
  end
end
