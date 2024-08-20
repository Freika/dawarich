# frozen_string_literal: true

class StatsSerializer
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    {
      totalDistanceKm: total_distance,
      totalPointsTracked: user.tracked_points.count,
      totalReverseGeocodedPoints: reverse_geocoded_points,
      totalCountriesVisited: user.countries_visited.count,
      totalCitiesVisited: user.cities_visited.count,
      yearlyStats: yearly_stats
    }.to_json
  end

  private

  def total_distance
    user.stats.sum(:distance)
  end

  def reverse_geocoded_points
    user.tracked_points.reverse_geocoded.count
  end

  def yearly_stats
    user.stats.group_by(&:year).sort.reverse.map do |year, stats|
      {
        year:,
        totalDistanceKm: stats.sum(&:distance),
        totalCountriesVisited: user.countries_visited.count,
        totalCitiesVisited: user.cities_visited.count,
        monthlyDistanceKm: monthly_distance(year, stats)
      }
    end
  end

  def monthly_distance(year, stats)
    months = {}

    (1..12).each { |month| months[Date::MONTHNAMES[month]&.downcase] = distance(month, year, stats) }

    months
  end

  def distance(month, year, stats)
    stats.find { _1.month == month && _1.year == year }&.distance.to_i
  end
end
