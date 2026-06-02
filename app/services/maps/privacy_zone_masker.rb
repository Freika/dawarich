# frozen_string_literal: true

module Maps
  class PrivacyZoneMasker
    Circle = Struct.new(:lon, :lat, :radius_meters, keyword_init: true)
    EARTH_RADIUS_M = 6_371_000.0

    delegate :any?, to: :circles

    def initialize(user)
      @user = user
    end

    def mask_points(relation)
      mask_relation(relation, 'points.lonlat')
    end

    def mask_places(relation)
      mask_relation(relation, 'places.lonlat')
    end

    def in_zone_place_ids
      return [] unless any?

      user.places.where(within_sql('places.lonlat'), *binds).pluck(:id)
    end

    def in_zone?(lon, lat)
      circles.any? { |c| haversine_m(lat, lon, c.lat, c.lon) <= c.radius_meters }
    end

    def mask_track_geojson(geojson)
      return geojson unless any?

      normalized = geojson.deep_stringify_keys
      features = Array(normalized['features']).flat_map { |feature| split_feature(feature) }

      normalized.merge('features' => features)
    end

    private

    attr_reader :user

    def mask_relation(relation, column)
      return relation unless any?

      relation.where("NOT (#{within_sql(column)})", *binds)
    end

    def within_sql(column)
      circles
        .map { "ST_DWithin(#{column}, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)" }
        .join(' OR ')
    end

    def binds
      circles.flat_map { |c| [c.lon, c.lat, c.radius_meters] }
    end

    def circles
      @circles ||= user.tags.privacy_zones.includes(:places).flat_map do |tag|
        tag.places.map do |place|
          Circle.new(lon: place.longitude.to_f, lat: place.latitude.to_f, radius_meters: tag.privacy_radius_meters)
        end
      end
    end

    def split_feature(feature)
      geometry = feature['geometry']
      lines =
        case geometry&.fetch('type', nil)
        when 'LineString' then [geometry['coordinates']]
        when 'MultiLineString' then geometry['coordinates']
        else return [feature]
        end

      lines.flat_map { |line| split_line(line) }.map do |segment|
        feature.merge(
          'geometry' => { 'type' => 'LineString', 'coordinates' => segment }
        )
      end
    end

    def split_line(coords)
      segments = []
      current = []

      coords.each do |(lon, lat)|
        if in_zone?(lon, lat)
          segments << current unless current.empty?
          current = []
        else
          current << [lon, lat]
        end
      end
      segments << current unless current.empty?

      segments.reject { |s| s.length < 2 }
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
