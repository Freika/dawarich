# frozen_string_literal: true

module Insights
  class ActivityHeatmapCalculator
    Result = Struct.new(
      :daily_data,
      :activity_levels,
      :max_distance,
      :active_days,
      :year,
      :current_streak,
      :longest_streak,
      :longest_streak_start,
      :longest_streak_end,
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
      streak_data = calculate_streaks(daily_data)

      Result.new(
        daily_data: daily_data,
        activity_levels: calculate_activity_levels(distances),
        max_distance: distances.max || 0,
        active_days: distances.size,
        year: @year,
        current_streak: streak_data[:current_streak],
        longest_streak: streak_data[:longest_streak],
        longest_streak_start: streak_data[:longest_streak_start],
        longest_streak_end: streak_data[:longest_streak_end]
      )
    end

    private

    def empty_result
      Result.new(
        daily_data: {},
        activity_levels: default_activity_levels,
        max_distance: 0,
        active_days: 0,
        year: @year,
        current_streak: 0,
        longest_streak: 0,
        longest_streak_start: nil,
        longest_streak_end: nil
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
      return daily_distance unless daily_distance.is_a?(Array)

      daily_distance.to_h
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

    def percentile(sorted_array, pct)
      return 0 if sorted_array.empty?

      k = (pct / 100.0 * (sorted_array.length - 1)).round
      sorted_array[k]
    end

    def default_activity_levels
      { p25: 1000, p50: 5000, p75: 10_000, p90: 20_000 }
    end

    def calculate_streaks(daily_data)
      return default_streak_data if daily_data.empty?

      active_dates = daily_data.select { |_, distance| distance.positive? }.keys.map { |d| Date.parse(d) }.sort
      return default_streak_data if active_dates.empty?

      longest_streak = 0
      longest_streak_start = nil
      longest_streak_end = nil
      current_streak = 0
      current_streak_start = nil

      active_dates.each_with_index do |date, index|
        if index.zero? || date == active_dates[index - 1] + 1
          current_streak += 1
          current_streak_start ||= date
        else
          current_streak = 1
          current_streak_start = date
        end

        next unless current_streak > longest_streak

        longest_streak = current_streak
        longest_streak_start = current_streak_start
        longest_streak_end = date
      end

      today = Date.current
      year_end = Date.new(@year, 12, 31)
      reference_date = [today, year_end].min

      final_current_streak = calculate_current_streak(active_dates, reference_date)

      {
        current_streak: final_current_streak,
        longest_streak: longest_streak,
        longest_streak_start: longest_streak_start,
        longest_streak_end: longest_streak_end
      }
    end

    def calculate_current_streak(active_dates, reference_date)
      return 0 if active_dates.empty?

      # Use Set for O(1) lookups instead of Array O(n)
      active_dates_set = active_dates.to_set

      streak = 0
      check_date = reference_date

      while active_dates_set.include?(check_date)
        streak += 1
        check_date -= 1
      end

      return streak if streak.positive?

      check_date = reference_date - 1

      while active_dates_set.include?(check_date)
        streak += 1
        check_date -= 1
      end

      streak
    end

    def default_streak_data
      { current_streak: 0, longest_streak: 0, longest_streak_start: nil, longest_streak_end: nil }
    end
  end
end
