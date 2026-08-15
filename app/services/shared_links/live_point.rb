# frozen_string_literal: true

module SharedLinks
  class LivePoint
    def initialize(user, lat:, lon:, timestamp:)
      @user = user
      @lat = lat
      @lon = lon
      @timestamp = timestamp
    end

    def call
      return { masked: true } if inside_privacy_zone?

      { lat: @lat.to_f, lon: @lon.to_f, ts: @timestamp.to_i }
    end

    private

    def inside_privacy_zone?
      zones = privacy_zones
      return false if zones.empty?

      clause = 'ST_DWithin(' \
               'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ' \
               'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)'
      condition = Array.new(zones.size, clause).join(' OR ')
      args = zones.flat_map { |z| [@lon.to_f, @lat.to_f, z[:lon], z[:lat], z[:radius]] }

      sql = ApplicationRecord.sanitize_sql_array(["SELECT EXISTS(SELECT 1 WHERE #{condition})", *args])
      ApplicationRecord.connection.select_value(sql)
    end

    def privacy_zones
      @user.tags.privacy_zones.includes(:places).flat_map do |tag|
        tag.places.map do |place|
          { lon: place.longitude.to_f, lat: place.latitude.to_f, radius: tag.privacy_radius_meters }
        end
      end
    end
  end
end
