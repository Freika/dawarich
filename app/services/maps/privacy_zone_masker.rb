# frozen_string_literal: true

module Maps
  class PrivacyZoneMasker
    Circle = Struct.new(:lon, :lat, :radius, keyword_init: true)

    EARTH_RADIUS_M = 6_371_000.0
    METERS_PER_DEGREE = Math::PI * EARTH_RADIUS_M / 180
    BUFFER_QUAD_SEGMENTS = 8
    COVERING_FACTOR = 1 / Math.cos(Math::PI / (4 * BUFFER_QUAD_SEGMENTS))

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
