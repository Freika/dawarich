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
      relation = user.scoped_visits
                     .left_outer_joins(:place, :area)
                     .includes(:place, :area)
                     .references(:place, :area)
                     .where(
                       "(#{PLACE_INSIDE}) OR (#{AREA_INSIDE})",
                       sw_lng, sw_lat, ne_lng, ne_lat,
                       sw_lng, sw_lat, ne_lng, ne_lat
                     )

      # Filter by started_at only — mirrors Visits::FindInTime; adding an
      # ended_at predicate silently drops boundary-crossing visits.
      relation = relation.where(started_at: start_at..end_at) if start_at && end_at

      relation.order(started_at: :desc)
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
