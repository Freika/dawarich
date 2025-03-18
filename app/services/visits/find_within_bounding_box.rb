# frozen_string_literal: true

module Visits
  # Finds visits in a selected area on the map
  class FindWithinBoundingBox
    def initialize(user, params)
      @user = user
      @sw_lat = params[:sw_lat].to_f
      @sw_lng = params[:sw_lng].to_f
      @ne_lat = params[:ne_lat].to_f
      @ne_lng = params[:ne_lng].to_f
    end

    def call
      bounding_box = "ST_MakeEnvelope(#{sw_lng}, #{sw_lat}, #{ne_lng}, #{ne_lat}, 4326)"

      Visit
        .includes(:place)
        .where(user:)
        .joins(:place)
        .where("ST_Contains(#{bounding_box}, ST_SetSRID(places.lonlat::geometry, 4326))")
        .order(started_at: :desc)
    end

    private

    attr_reader :user, :sw_lat, :sw_lng, :ne_lat, :ne_lng
  end
end
