# frozen_string_literal: true

module Timeline
  module DayBounds
    private

    def masked_path_sql
      path = 'original_path::geometry'
      return path unless @privacy_zone_masker&.any?

      "CASE WHEN #{@privacy_zone_masker.touches_sql(path)} THEN #{@privacy_zone_masker.clip_sql(path)} ELSE #{path} END"
    end

    def build_bounds(visits, tracks)
      lats = []
      lngs = []

      visits.each do |visit|
        coords = visit.place ? visible_coordinates(visit.place.lat, visit.place.lon) : point_center_for(visit)
        next if coords.nil? || coords[:lat].nil? || coords[:lng].nil?

        lats << coords[:lat]
        lngs << coords[:lng]
      end

      track_extent = tracks_extent(tracks)
      if track_extent
        lats << track_extent[:min_lat] << track_extent[:max_lat]
        lngs << track_extent[:min_lng] << track_extent[:max_lng]
      end

      return nil if lats.empty? || lngs.empty?

      {
        sw_lat: lats.min,
        sw_lng: lngs.min,
        ne_lat: lats.max,
        ne_lng: lngs.max
      }
    end

    def tracks_extent(tracks)
      track_ids = tracks.map(&:id)
      return nil if track_ids.empty?

      query = <<~SQL.squish
        SELECT
          ST_XMin(extent) AS min_lng,
          ST_YMin(extent) AS min_lat,
          ST_XMax(extent) AS max_lng,
          ST_YMax(extent) AS max_lat
        FROM (
          SELECT ST_Extent(#{masked_path_sql}) AS extent
          FROM tracks
          WHERE id IN (?) AND original_path IS NOT NULL
        ) sub
      SQL
      sql = ActiveRecord::Base.sanitize_sql_array([query, track_ids])

      row = ActiveRecord::Base.connection.exec_query(sql).first
      return nil unless row && row['min_lng']

      {
        min_lng: row['min_lng'].to_f,
        min_lat: row['min_lat'].to_f,
        max_lng: row['max_lng'].to_f,
        max_lat: row['max_lat'].to_f
      }
    end
  end
end
