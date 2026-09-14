# frozen_string_literal: true

module Visits
  class FindInTime
    def initialize(user, params)
      @user = user
      @start_at = parse_time(params[:start_at])
      @end_at = parse_time(params[:end_at])
    end

    def call
      # Filter by started_at only; adding ended_at <= end_at silently drops
      # boundary-crossing visits and breaks marker rendering on the timeline.
      user.scoped_visits
          .includes(:place, :area)
          .where(started_at: start_at..end_at)
          .order(started_at: :asc)
    end

    private

    attr_reader :user, :start_at, :end_at

    def parse_time(time_string)
      Time.zone.parse(time_string) || raise(Visits::InvalidTimeRange)
    rescue ArgumentError, TypeError
      raise Visits::InvalidTimeRange
    end
  end
end
