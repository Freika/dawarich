# frozen_string_literal: true

module Visits
  class PointCenters
    LATITUDE = 'AVG(ST_Y(points.lonlat::geometry))'
    LONGITUDE = 'AVG(ST_X(points.lonlat::geometry))'
    GEOGRAPHY = "ST_SetSRID(ST_MakePoint(#{LONGITUDE}, #{LATITUDE}), 4326)::geography".freeze

    def initialize(user, visit_ids:, privacy_zone_masker: nil)
      @user = user
      @visit_ids = visit_ids
      @privacy_zone_masker = privacy_zone_masker
    end

    def call
      scope.pluck(:visit_id, Arel.sql(LATITUDE), Arel.sql(LONGITUDE))
           .each_with_object({}) do |(id, lat, lng), centers|
        next if lat.nil? || lng.nil? || @privacy_zone_masker&.in_zone?(lng, lat)

        centers[id] = { lat: lat, lng: lng }
      end
    end

    def within_bounds(sw_lng:, sw_lat:, ne_lng:, ne_lat:)
      relation = scope.select(:visit_id).having(
        "ST_Contains(ST_MakeEnvelope(?, ?, ?, ?, 4326), (#{GEOGRAPHY})::geometry)",
        sw_lng, sw_lat, ne_lng, ne_lat
      )
      return relation unless @privacy_zone_masker&.any?

      relation.having("NOT #{@privacy_zone_masker.within_sql(GEOGRAPHY)}")
    end

    private

    def scope
      @user.scoped_points.where(visit_id: @visit_ids).group(:visit_id)
    end
  end
end
