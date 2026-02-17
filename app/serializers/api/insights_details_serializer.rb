# frozen_string_literal: true

class Api::InsightsDetailsSerializer
  def initialize(year:, comparison:, travel_patterns:)
    @year = year
    @comparison = comparison
    @travel_patterns = travel_patterns
  end

  def call
    {
      year: year,
      comparison: serialize_comparison,
      travelPatterns: serialize_travel_patterns
    }
  end

  private

  attr_reader :year, :comparison, :travel_patterns

  def serialize_comparison
    return nil unless comparison

    {
      previousYear: year - 1,
      distanceChangePercent: comparison.distance_change,
      countriesChange: comparison.countries_change,
      citiesChange: comparison.cities_change,
      daysChange: comparison.days_change
    }
  end

  def serialize_travel_patterns
    {
      timeOfDay: travel_patterns[:time_of_day] || {},
      dayOfWeek: travel_patterns[:day_of_week] || Array.new(7, 0),
      seasonality: travel_patterns[:seasonality] || {},
      activityBreakdown: travel_patterns[:activity_breakdown] || {},
      topVisitedLocations: travel_patterns[:top_visited_locations] || []
    }
  end
end
