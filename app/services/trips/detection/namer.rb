# frozen_string_literal: true

module Trips
  module Detection
    # Names a Detected Trip in the current locale: the city with the most days for
    # a one-country trip, up to three countries in order of arrival otherwise,
    # and the date range when neither is known.
    class Namer
      MAX_COUNTRIES = 3

      def initialize(user, started_at:, ended_at:)
        @user = user
        @zone = user.timezone_iana
        @trip = Trip.new(user:, started_at:, ended_at:)
        @start_date = started_at.in_time_zone(@zone).to_date
        @end_date = ended_at.in_time_zone(@zone).to_date
      end

      def call
        @trip.calculate_countries
        countries = @trip.canonical_visited_countries
        places = countries.size > 1 ? countries.first(MAX_COUNTRIES) : [top_city || countries.first].compact
        return fallback if places.empty?

        I18n.t('trip_detection.name', places: places.join(I18n.t('trip_detection.list_separator')),
                                      month: I18n.l(@start_date, format: I18n.t('trip_detection.formats.month_year')))
      end

      def fallback
        I18n.t('trip_detection.fallback_name', range:)
      end

      private

      def range
        return I18n.l(@end_date, format: I18n.t('trip_detection.range.same_month.end')) if @start_date == @end_date

        span = if @start_date.year != @end_date.year then 'cross_year'
               elsif @start_date.month != @end_date.month then 'same_year'
               else 'same_month'
               end
        I18n.t("trip_detection.range.#{span}.pattern",
               start: I18n.l(@start_date, format: I18n.t("trip_detection.range.#{span}.start")),
               end: I18n.l(@end_date, format: I18n.t("trip_detection.range.#{span}.end")))
      end

      def top_city
        day = "(to_timestamp(points.timestamp) AT TIME ZONE #{Point.connection.quote(@zone)})::date"

        @trip.points.not_flyover.where.not(city: [nil, '']).reorder(nil).group(:city)
             .order(Arel.sql("COUNT(DISTINCT #{day}) DESC, MIN(points.timestamp)"))
             .pick(:city)
      end
    end
  end
end
