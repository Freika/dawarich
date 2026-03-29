# frozen_string_literal: true

class StatsSerializer
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    {
      totalDistanceKm: total_distance_km,
      totalPointsTracked: user.points_count.to_i,
      totalReverseGeocodedPoints: reverse_geocoded_points,
      totalCountriesVisited: user.countries_visited.count,
      totalCitiesVisited: user.cities_visited.count,
      yearlyStats: yearly_stats
    }.to_json
  end

  private

  def total_distance_km
    total_distance_meters = user.stats.sum(:distance)

    (total_distance_meters / 1000)
  end

  def reverse_geocoded_points
    StatsQuery.new(user).points_stats[:geocoded]
  end

  def yearly_stats
    user.stats.group_by(&:year).sort.reverse.map do |year, stats|
      countries, cities = countries_and_cities_from_stats(stats)

      {
        year:,
        totalDistanceKm: stats_distance_km(stats),
        totalCountriesVisited: countries.count,
        totalCitiesVisited: cities.count,
        monthlyDistanceKm: monthly_distance(year, stats)
      }
    end
  end

  def stats_distance_km(stats)
    # Convert from stored meters to kilometers
    total_meters = stats.sum(&:distance)
    total_meters / 1000
  end

  def monthly_distance(year, stats)
    months = {}

    (1..12).each { |month| months[Date::MONTHNAMES[month]&.downcase] = distance_km(month, year, stats) }

    months
  end

  def distance_km(month, year, stats)
    # Convert from stored meters to kilometers
    distance_meters = stats.find { _1.month == month && _1.year == year }&.distance.to_i

    distance_meters / 1000
  end

  def countries_and_cities_from_stats(stats)
    countries = Set.new
    cities = Set.new

    stats.each do |stat|
      toponyms = stat.toponyms
      next unless toponyms.is_a?(Array)

      toponyms.each do |toponym|
        next unless toponym.is_a?(Hash)
        next if toponym['country'].blank?
        next unless toponym['cities'].is_a?(Array) && toponym['cities'].any?

        countries.add(toponym['country'])
        toponym['cities'].each do |city|
          cities.add(city['city']) if city.is_a?(Hash) && city['city'].present?
        end
      end
    end

    [countries, cities]
  end
end
