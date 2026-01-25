# frozen_string_literal: true

module Insights
  class ActivityHeatmapCalculator
    Result = Struct.new(
      :daily_data,
      :activity_levels,
      :max_distance,
      :active_days,
      :year,
      keyword_init: true
    )

    def initialize(stats, year)
      @stats = stats
      @year = year
    end

    def call
      return empty_result if @stats.empty?

      daily_data = aggregate_daily_distances
      distances = daily_data.values.select(&:positive?)

      Result.new(
        daily_data: daily_data,
        activity_levels: calculate_activity_levels(distances),
        max_distance: distances.max || 0,
        active_days: distances.size,
        year: @year
      )
    end

    private

    def empty_result
      Result.new(
        daily_data: {},
        activity_levels: default_activity_levels,
        max_distance: 0,
        active_days: 0,
        year: @year
      )
    end

    def aggregate_daily_distances
      daily_data = {}

      @stats.each do |stat|
        next unless stat.daily_distance.is_a?(Hash) || stat.daily_distance.is_a?(Array)

        daily_distance = normalize_daily_distance(stat.daily_distance)
        daily_distance.each do |day_number, distance|
          date = build_date(stat.year, stat.month, day_number.to_i)
          next unless date

          date_key = date.strftime('%Y-%m-%d')
          daily_data[date_key] = (daily_data[date_key] || 0) + distance.to_i
        end
      end

      daily_data
    end

    def normalize_daily_distance(daily_distance)
      if daily_distance.is_a?(Array)
        daily_distance.to_h
      else
        daily_distance
      end
    end

    def build_date(year, month, day)
      Date.new(year, month, day)
    rescue ArgumentError
      nil
    end

    def calculate_activity_levels(distances)
      return default_activity_levels if distances.empty?

      sorted = distances.sort

      {
        p25: percentile(sorted, 25),
        p50: percentile(sorted, 50),
        p75: percentile(sorted, 75),
        p90: percentile(sorted, 90)
      }
    end

    def percentile(sorted_array, p)
      return 0 if sorted_array.empty?

      k = (p / 100.0 * (sorted_array.length - 1)).round
      sorted_array[k]
    end

    def default_activity_levels
      { p25: 1000, p50: 5000, p75: 10_000, p90: 20_000 }
    end
  end
end
