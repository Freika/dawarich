# frozen_string_literal: true

class Api::DigestDetailSerializer
  def initialize(digest, distance_unit:)
    @digest = digest
    @distance_unit = distance_unit
  end

  def call
    {
      year: digest.year,
      distance: serialize_distance,
      toponyms: serialize_toponyms,
      monthlyDistances: serialize_monthly_distances,
      timeSpentByLocation: digest.time_spent_by_location,
      firstTimeVisits: digest.first_time_visits,
      yearOverYear: serialize_year_over_year,
      allTimeStats: serialize_all_time_stats,
      travelPatterns: serialize_travel_patterns,
      createdAt: digest.created_at.iso8601,
      updatedAt: digest.updated_at.iso8601
    }
  end

  private

  attr_reader :digest, :distance_unit

  def serialize_monthly_distances
    month_names = %w[january february march april may june july august september october november december]
    raw = digest.monthly_distances || {}

    month_names.each_with_index.to_h do |name, i|
      [name, raw[(i + 1).to_s].to_f]
    end
  end

  def serialize_distance
    converted = digest.distance_in_unit(distance_unit).round
    {
      meters: digest.distance.to_i,
      converted: converted,
      unit: distance_unit,
      comparisonText: digest.distance_comparison_text
    }
  end

  def serialize_toponyms
    countries = (digest.toponyms || []).select { |t| t['country'].present? }.map do |toponym|
      {
        country: toponym['country'],
        cities: (toponym['cities'] || []).map { |c| c['city'] }.compact
      }
    end

    {
      countriesCount: digest.countries_count,
      citiesCount: digest.cities_count,
      countries: countries
    }
  end

  def serialize_year_over_year
    yoy = digest.year_over_year
    return nil if yoy.blank?

    {
      distanceChangePercent: yoy['distance_change_percent'],
      countriesChange: yoy['countries_change'],
      citiesChange: yoy['cities_change']
    }
  end

  def serialize_all_time_stats
    stats = digest.all_time_stats || {}
    {
      totalCountries: stats['total_countries'] || 0,
      totalCities: stats['total_cities'] || 0,
      totalDistance: (stats['total_distance'] || 0).to_s
    }
  end

  def serialize_travel_patterns
    patterns = digest.travel_patterns || {}
    {
      timeOfDay: patterns['time_of_day'] || {},
      seasonality: patterns['seasonality'] || {},
      activityBreakdown: patterns['activity_breakdown'] || {}
    }
  end
end
