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
      if ActiveModel::Type::Boolean.new.cast(params[:mask_privacy_zones])
        @privacy_zone_masker = Maps::PrivacyZoneMasker.new(user)
      end
      @sw_lat = params[:sw_lat].to_f
      @sw_lng = params[:sw_lng].to_f
      @ne_lat = params[:ne_lat].to_f
      @ne_lng = params[:ne_lng].to_f
      raise Visits::InvalidTimeRange if params[:start_at].present? != params[:end_at].present?

      @start_at = parse_time(params[:start_at])
      @end_at = parse_time(params[:end_at])
      raise Visits::InvalidTimeRange if @start_at && @start_at > @end_at
    end

    def call
      visits = user.scoped_visits
      visits = visits.where(started_at: start_at..end_at) if start_at && end_at
      unlocated = visits.where(place_id: nil, area_id: nil)
      centers = PointCenters.new(user, visit_ids: unlocated.select(:id), privacy_zone_masker: @privacy_zone_masker)
                            .within_bounds(sw_lng: sw_lng, sw_lat: sw_lat, ne_lng: ne_lng, ne_lat: ne_lat)
      relation = visits.left_outer_joins(:place, :area)
                       .includes(:area, place: :legacy_area_place_mappings)
                       .references(:place, :area)
      located = relation.where(
        "(#{PLACE_INSIDE}) OR (#{AREA_INSIDE})",
        sw_lng, sw_lat, ne_lng, ne_lat,
        sw_lng, sw_lat, ne_lng, ne_lat
      )

      located.or(relation.where(id: centers)).order(started_at: :desc)
    end

    private

    attr_reader :user, :sw_lat, :sw_lng, :ne_lat, :ne_lng, :start_at, :end_at

    def parse_time(time_string)
      return nil if time_string.blank?

      Visits::TimeValue.parse(time_string) || raise(Visits::InvalidTimeRange)
    end
  end
end
