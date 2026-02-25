# frozen_string_literal: true

module Insights
  class YearComparisonCalculator
    Result = Struct.new(
      :prev_total_distance,
      :prev_countries_count,
      :prev_cities_count,
      :prev_days_traveling,
      :prev_biggest_month,
      :distance_change,
      :countries_change,
      :cities_change,
      :days_change,
      keyword_init: true
    )

    def initialize(current_totals, previous_year_stats, distance_unit:)
      @current_totals = current_totals
      @previous_year_stats = previous_year_stats
      @distance_unit = distance_unit
    end

    def call
      prev_totals = YearTotalsCalculator.new(previous_year_stats, distance_unit: distance_unit).call

      Result.new(
        prev_total_distance: prev_totals.total_distance,
        prev_countries_count: prev_totals.countries_count,
        prev_cities_count: prev_totals.cities_count,
        prev_days_traveling: prev_totals.days_traveling,
        prev_biggest_month: prev_totals.biggest_month,
        distance_change: calculate_change(current_totals.total_distance, prev_totals.total_distance),
        countries_change: current_totals.countries_count - prev_totals.countries_count,
        cities_change: calculate_change(current_totals.cities_count, prev_totals.cities_count),
        days_change: calculate_change(current_totals.days_traveling, prev_totals.days_traveling)
      )
    end

    private

    attr_reader :current_totals, :previous_year_stats, :distance_unit

    def calculate_change(current, previous)
      return 0 if previous.nil? || previous.zero?

      ((current - previous).to_f / previous * 100).round
    end
  end
end
