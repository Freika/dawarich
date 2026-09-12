# frozen_string_literal: true

module Users
  module Digests
    class CountryMinutesCalculator
      MINUTES_PER_DAY = 1440
      MINIMUM_SPAN_SECONDS = 60
      TOP_COUNTRIES_LIMIT = 10

      def initialize(points, timezone)
        @points = points
        @timezone = timezone
      end

      def call
        @call ||= minutes_by_country
      end

      def top_countries(limit = TOP_COUNTRIES_LIMIT)
        call
          .sort_by { |_, minutes| -minutes }
          .first(limit)
          .map { |name, minutes| { 'name' => name, 'minutes' => minutes } }
      end

      def total_minutes
        call.values.sum
      end

      private

      attr_reader :points, :timezone

      def minutes_by_country
        country_minutes = Hash.new(0)

        points_by_date.each_value do |day_points|
          countries_on_day = day_points.map(&:country_name).uniq

          if countries_on_day.size == 1
            country_minutes[countries_on_day.first] += MINUTES_PER_DAY
          else
            add_proportional_time(day_points, country_minutes)
          end
        end

        country_minutes
      end

      def points_by_date
        points.group_by { |point| timezone.at(point.timestamp).to_date }
      end

      def add_proportional_time(day_points, country_minutes)
        country_spans = spans_by_country(day_points)
        total_spans = country_spans.values.sum.to_f

        country_spans.each do |country, span|
          country_minutes[country] += (span / total_spans * MINUTES_PER_DAY).round
        end
      end

      def spans_by_country(day_points)
        day_points.group_by(&:country_name).transform_values do |country_points|
          timestamps = country_points.map(&:timestamp)

          [timestamps.max - timestamps.min, MINIMUM_SPAN_SECONDS].max
        end
      end
    end
  end
end
