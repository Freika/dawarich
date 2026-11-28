# frozen_string_literal: true

# Countries and cities a user has been to, aggregated from Stat toponyms.
module VisitedPlaces
  extend ActiveSupport::Concern

  def countries_visited
    Rails.cache.fetch(Cache::UserKeys.countries_visited(id), expires_in: 1.day) do
      countries_visited_uncached
    end
  end

  def cities_visited
    Rails.cache.fetch(Cache::UserKeys.cities_visited(id), expires_in: 1.day) do
      cities_visited_uncached
    end
  end

  def total_countries
    countries_visited.size
  end

  def total_cities
    cities_visited.size
  end

  # Includes countries even when no city meets the minimum stay threshold
  def countries_visited_uncached
    countries = Set.new

    each_toponym { |toponym| countries.add(toponym['country']) if toponym['country'].present? }

    countries.to_a.sort
  end

  # This respects min_minutes_spent_in_city since toponyms are already filtered
  def cities_visited_uncached
    cities = Set.new

    each_toponym do |toponym|
      next unless toponym['cities'].is_a?(Array)

      toponym['cities'].each do |city|
        cities.add(city['city']) if city.is_a?(Hash) && city['city'].present?
      end
    end

    cities.to_a.sort
  end

  private

  def each_toponym
    stats.select(:id, :toponyms).find_each do |stat|
      next unless stat.toponyms.is_a?(Array)

      stat.toponyms.each { |toponym| yield toponym if toponym.is_a?(Hash) }
    end
  end
end
