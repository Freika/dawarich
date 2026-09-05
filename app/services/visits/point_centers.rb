# frozen_string_literal: true

module Visits
  # The same arithmetic center as Visit#center, without instantiating Point
  # objects. Both marker coordinates and rectangle selection use this center.
  # Callers restrict visit_ids to the displayed/queried unlocated visits;
  # points also retain their owner's plan visibility scope.
  class PointCenters
    LATITUDE = 'AVG(ST_Y(points.lonlat::geometry))'
    LONGITUDE = 'AVG(ST_X(points.lonlat::geometry))'

    def initialize(user, visit_ids:)
      @user = user
      @visit_ids = visit_ids
    end

    def call
      scope.pluck(:visit_id, Arel.sql(LATITUDE), Arel.sql(LONGITUDE))
           .each_with_object({}) do |(id, lat, lng), centers|
        centers[id] = { lat: lat, lng: lng } if lat && lng
      end
    end

    def within_bounds(sw_lng:, sw_lat:, ne_lng:, ne_lat:)
      scope.select(:visit_id).having(
        "ST_Contains(ST_MakeEnvelope(?, ?, ?, ?, 4326), ST_SetSRID(ST_MakePoint(#{LONGITUDE}, #{LATITUDE}), 4326))",
        sw_lng, sw_lat, ne_lng, ne_lat
      )
    end

    private

    def scope
      @user.scoped_points.where(visit_id: @visit_ids).group(:visit_id)
    end
  end
end
