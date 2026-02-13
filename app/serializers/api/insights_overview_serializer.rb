# frozen_string_literal: true

class Api::InsightsOverviewSerializer
  def initialize(year:, available_years:, totals:, heatmap:, distance_unit:)
    @year = year
    @available_years = available_years
    @totals = totals
    @heatmap = heatmap
    @distance_unit = distance_unit
  end

  def call
    {
      year: year,
      availableYears: available_years,
      totals: serialize_totals,
      activityHeatmap: serialize_heatmap
    }
  end

  private

  attr_reader :year, :available_years, :totals, :heatmap, :distance_unit

  def serialize_totals
    {
      totalDistance: totals.total_distance,
      distanceUnit: distance_unit,
      countriesCount: totals.countries_count,
      citiesCount: totals.cities_count,
      countriesList: totals.countries_list,
      daysTraveling: totals.days_traveling,
      biggestMonth: totals.biggest_month
    }
  end

  def serialize_heatmap
    return nil unless heatmap

    {
      dailyData: heatmap.daily_data,
      activityLevels: heatmap.activity_levels,
      maxDistance: heatmap.max_distance,
      activeDays: heatmap.active_days,
      currentStreak: heatmap.current_streak,
      longestStreak: heatmap.longest_streak,
      longestStreakStart: heatmap.longest_streak_start&.to_s,
      longestStreakEnd: heatmap.longest_streak_end&.to_s
    }
  end
end
