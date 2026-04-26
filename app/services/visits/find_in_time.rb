# frozen_string_literal: true

module Visits
  class FindInTime
    def initialize(user, params)
      @user = user
      @start_at = parse_time(params[:start_at])
      @end_at = parse_time(params[:end_at])
    end

    def call
      # Match DayAssembler: bucket by `started_at` only. Anchoring on
      # `ended_at <= end_at` (the previous form) silently dropped visits
      # crossing the range boundary — the timeline rail listed them but
      # the map didn't render their markers. Suggested visits are
      # over-represented because they're often auto-detected long stays
      # that span midnight.
      user.scoped_visits
          .includes(:place, :area)
          .where(started_at: start_at..end_at)
          .order(started_at: :desc)
    end

    private

    attr_reader :user, :start_at, :end_at

    def parse_time(time_string)
      parsed_time = Time.zone.parse(time_string)

      raise ArgumentError, "Invalid time format: #{time_string}" if parsed_time.nil?

      parsed_time
    end
  end
end
