# frozen_string_literal: true

module Maps
  class PrivacyZoneMasker
    Circle = Struct.new(:lon, :lat, :radius, keyword_init: true)

    EARTH_RADIUS_M = 6_371_000.0
    METERS_PER_DEGREE = Math::PI * EARTH_RADIUS_M / 180
    BUFFER_QUAD_SEGMENTS = 8
    COVERING_FACTOR = 1 / Math.cos(Math::PI / (4 * BUFFER_QUAD_SEGMENTS))
    TILE_MARGIN = 0.125

    def initialize(user, circles: nil)
      @user = user
      @circles = circles
    end

    delegate :any?, to: :circles

    def mask_points(relation)
      mask_relation(relation, 'points.lonlat')
    end

    def mask_places(relation)
      mask_relation(relation, 'places.lonlat')
    end

    def in_zone_place_ids
      return [] unless any?

      @user.places.where(within_sql('places.lonlat')).pluck(:id)
    end

    def in_zone_area_ids
      return [] unless any?

      @user.areas.where(within_sql('ST_SetSRID(ST_MakePoint(areas.longitude, areas.latitude), 4326)::geography'))
           .pluck(:id)
    end

    def mask_visits(visits)
      return visits unless any?

      place_ids = in_zone_place_ids
      area_ids = in_zone_area_ids
      unless visits.is_a?(ActiveRecord::Relation)
        return visits.reject do |visit|
          visit.place_id ? place_ids.include?(visit.place_id) : area_ids.include?(visit.area_id)
        end
      end

      visits = visits.where('visits.place_id IS NULL OR visits.place_id NOT IN (?)', place_ids) if place_ids.any?
      return visits if area_ids.none?

      visits.where('visits.place_id IS NOT NULL OR visits.area_id IS NULL OR visits.area_id NOT IN (?)', area_ids)
    end

    def mask_photos(photos)
      return photos unless any?

      photos.reject do |photo|
        in_zone?(photo['longitude'] || photo[:longitude], photo['latitude'] || photo[:latitude])
      end
    end

    def mask_track_features(geojson)
      return geojson unless any?

      features = Array(geojson[:features]).filter_map do |feature|
        geometry = clip_geojson(feature[:geometry])
        next if geometry.nil?

        mask_segments(feature[:properties])
        feature.merge(geometry: geometry)
      end
      geojson.merge(features: features)
    end

    def clip_geojson(geometry)
      return geometry unless any? && geometry

      lons, lats = geojson_coordinates(geometry).transpose
      return geometry if lons.nil?

      nearby = near(min_lon: lons.min, min_lat: lats.min, max_lon: lons.max, max_lat: lats.max)
      return geometry unless nearby.any?

      clipped = nearby.clipped_geojson_text(geometry.to_json)
      clipped && JSON.parse(clipped, symbolize_names: true)
    end

    def clipped_geojson_text(geojson_text)
      source = "ST_SetSRID(ST_GeomFromGeoJSON(#{ActiveRecord::Base.connection.quote(geojson_text)}), 4326)"
      ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT CASE WHEN ST_IsEmpty(clipped) THEN NULL ELSE ST_AsGeoJSON(clipped) END
        FROM (SELECT #{clip_sql(source)} AS clipped) AS result
      SQL
    end

    def in_zone?(lon, lat)
      return false if lon.nil? || lat.nil?

      circles.any? { |c| haversine_m(lat.to_f, lon.to_f, c.lat, c.lon) <= c.radius }
    end

    def within_sql(geography_sql)
      return 'FALSE' unless any?

      conditions = circles.map { |c| "ST_DWithin(#{geography_sql}, #{point_sql(c)}, #{c.radius}, false)" }
      "(#{conditions.join(' OR ')})"
    end

    def touches_sql(geometry_sql)
      return 'FALSE' unless any?

      conditions = circles.map do |c|
        "(#{geometry_sql} && #{expanded_box_sql(c)} AND " \
          "ST_DWithin((#{geometry_sql})::geography, #{point_sql(c)}, #{c.radius}, false))"
      end
      "(#{conditions.join(' OR ')})"
    end

    def clip_sql(geometry_sql)
      return geometry_sql unless any?

      buffers = circles.map do |c|
        "ST_Buffer(#{point_sql(c)}, #{c.radius * COVERING_FACTOR}, 'quad_segs=#{BUFFER_QUAD_SEGMENTS}')::geometry"
      end
      "ST_Difference(#{geometry_sql}, ST_Union(ARRAY[#{buffers.join(', ')}]))"
    end

    def fingerprint
      return nil unless any?

      Digest::SHA256.hexdigest(circles.map { |c| [c.lon, c.lat, c.radius] }.sort.to_json)
    end

    def near(min_lon:, min_lat:, max_lon:, max_lat:)
      nearby = circles.select do |c|
        dlat, dlon = degree_reach(c)
        c.lon + dlon >= min_lon && c.lon - dlon <= max_lon &&
          c.lat + dlat >= min_lat && c.lat - dlat <= max_lat
      end
      self.class.new(@user, circles: nearby)
    end

    def near_tile(zoom, column, row)
      bbox = self.class.tile_bbox(zoom, column, row, margin: TILE_MARGIN)
      bbox ? near(**bbox) : self
    end

    def covers_tile?(zoom, column, row)
      bbox = self.class.tile_bbox(zoom, column, row)
      bbox.present? && covers_bbox?(**bbox)
    end

    def self.tile_bbox(zoom, column, row, margin: 0)
      zoom = Integer(zoom, exception: false)
      column = Integer(column, exception: false)
      row = Integer(row, exception: false)
      return if [zoom, column, row].any?(&:nil?) || zoom.negative? || zoom > 30

      count = 2**zoom
      return unless column.between?(0, count - 1) && row.between?(0, count - 1)

      { min_lon: tile_lon(column - margin, count), max_lon: tile_lon(column + 1 + margin, count),
        min_lat: tile_lat(row + 1 + margin, count), max_lat: tile_lat(row - margin, count) }
    end

    def self.tile_lon(column, count)
      (column.to_f / count * 360.0) - 180.0
    end

    def self.tile_lat(row, count)
      Math.atan(Math.sinh(Math::PI * (1 - (2.0 * row / count)))) * 180.0 / Math::PI
    end

    def covers_bbox?(min_lon:, min_lat:, max_lon:, max_lat:)
      corners = [[min_lon, min_lat], [min_lon, max_lat], [max_lon, min_lat], [max_lon, max_lat]]
      circles.any? do |c|
        corners.all? { |lon, lat| haversine_m(lat, lon, c.lat, c.lon) <= c.radius }
      end
    end

    private

    def circles
      @circles ||= Users::PrivacyZones.new(@user).call.map do |zone|
        Circle.new(lon: zone[:lon].to_f, lat: zone[:lat].to_f, radius: zone[:radius].to_f)
      end
    end

    def mask_segments(properties)
      return unless properties.is_a?(Hash) && properties[:segments].is_a?(Array)

      properties[:segments] = properties[:segments].filter_map do |segment|
        next segment if segment[:coordinates].blank?

        geometry = clip_geojson(type: 'LineString', coordinates: segment[:coordinates])
        geometry && segment.merge(coordinates: geometry[:coordinates])
      end
    end

    def geojson_coordinates(geometry)
      case geometry[:type].to_s
      when 'LineString', 'MultiPoint' then geometry[:coordinates]
      when 'MultiLineString', 'Polygon' then geometry[:coordinates].flatten(1)
      when 'Point' then [geometry[:coordinates]]
      else []
      end
    end

    def mask_relation(relation, column)
      return relation unless any?

      relation.where("NOT #{within_sql(column)}")
    end

    def point_sql(circle)
      "ST_SetSRID(ST_MakePoint(#{circle.lon}, #{circle.lat}), 4326)::geography"
    end

    def expanded_box_sql(circle)
      dlat, dlon = degree_reach(circle)
      "ST_Expand(ST_SetSRID(ST_MakePoint(#{circle.lon}, #{circle.lat}), 4326), #{dlon}, #{dlat})"
    end

    def degree_reach(circle)
      dlat = circle.radius * COVERING_FACTOR / METERS_PER_DEGREE * 1.01
      cos_lat = [Math.cos(circle.lat.abs.clamp(0, 89) * Math::PI / 180), 0.01].max
      [dlat, dlat / cos_lat]
    end

    def haversine_m(lat1, lon1, lat2, lon2)
      rad = Math::PI / 180
      d_lat = (lat2 - lat1) * rad
      d_lon = (lon2 - lon1) * rad
      a = (Math.sin(d_lat / 2)**2) +
          (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(d_lon / 2)**2))
      2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(a))
    end
  end
end
