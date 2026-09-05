# frozen_string_literal: true

module Visits
  # Finds visits in a selected area on the map
  class FindWithinBoundingBox
    PLACE_INSIDE = 'places.lonlat IS NOT NULL AND ' \
                   'ST_Contains(ST_MakeEnvelope(?, ?, ?, ?, 4326), ' \
                   'ST_SetSRID(places.lonlat::geometry, 4326))'

    AREA_INSIDE = 'areas.id IS NOT NULL AND ' \
                  'ST_Contains(ST_MakeEnvelope(?, ?, ?, ?, 4326), ' \
                  'ST_SetSRID(ST_MakePoint(areas.longitude, areas.latitude), 4326))'

    def initialize(user, params)
      @user = user
      @sw_lat = params[:sw_lat].to_f
      @sw_lng = params[:sw_lng].to_f
      @ne_lat = params[:ne_lat].to_f
      @ne_lng = params[:ne_lng].to_f
      @start_at = parse_time(params[:start_at])
      @end_at = parse_time(params[:end_at])
    end

    def call
      # Apply the same dates and visibility scope to the GPS aggregate as to
      # the result. In particular, do not scan unrelated historical visits.
      visits = user.scoped_visits
      visits = visits.where(started_at: start_at..end_at) if start_at && end_at
      unlocated = visits.where(place_id: nil, area_id: nil)
      point_centers_inside = Visits::PointCenters.new(user, visit_ids: unlocated.select(:id))
                                                 .within_bounds(sw_lng: sw_lng, sw_lat: sw_lat,
                                                                ne_lng: ne_lng, ne_lat: ne_lat)
      relation = visits.left_outer_joins(:place, :area)
                       .includes(:place, :area)
                       .references(:place, :area)
      located = relation.where(
        "(#{PLACE_INSIDE}) OR (#{AREA_INSIDE})",
        sw_lng, sw_lat, ne_lng, ne_lat,
        sw_lng, sw_lat, ne_lng, ne_lat
      )

      located.or(relation.where(id: point_centers_inside)).order(started_at: :desc)
    end

    private

    attr_reader :user, :sw_lat, :sw_lng, :ne_lat, :ne_lng, :start_at, :end_at

    def parse_time(time_string)
      return nil if time_string.blank?

      Time.zone.parse(time_string.to_s)
    rescue ArgumentError
      nil
    end
  end
end
