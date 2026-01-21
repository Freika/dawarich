# frozen_string_literal: true

module Insights
  class YearTotalsCalculator
    Result = Struct.new(
      :total_distance,
      :countries_count,
      :cities_count,
      :countries_list,
      :days_traveling,
      :biggest_month,
      keyword_init: true
    )

    def initialize(stats, distance_unit:)
      @stats = stats
      @distance_unit = distance_unit
    end

    def call
      countries = Set.new
      cities = Set.new

      extract_toponyms(countries, cities)

      Result.new(
        total_distance: calculate_total_distance,
        countries_count: countries.size,
        cities_count: cities.size,
        countries_list: countries.to_a.sort,
        days_traveling: calculate_days_traveling,
        biggest_month: find_biggest_month
      )
    end

    private

    attr_reader :stats, :distance_unit

    def calculate_total_distance
      total_distance_meters = stats.sum(:distance)
      Stat.convert_distance(total_distance_meters, distance_unit).round
    end

    def extract_toponyms(countries, cities)
      stats.each do |stat|
        next unless stat.toponyms.is_a?(Array)

        stat.toponyms.each do |toponym|
          next unless toponym.is_a?(Hash)

          countries.add(toponym['country']) if toponym['country'].present?

          next unless toponym['cities'].is_a?(Array)

          toponym['cities'].each do |city|
            cities.add(city['city']) if city.is_a?(Hash) && city['city'].present?
          end
        end
      end
    end

    def calculate_days_traveling
      stats.sum do |stat|
        stat.daily_distance.count { |_day, distance| distance.to_i.positive? }
      end
    end

    def find_biggest_month
      return nil if stats.empty?

      max_stat = stats.max_by(&:distance)
      return nil unless max_stat&.distance&.positive?

      {
        month: Date::MONTHNAMES[max_stat.month],
        distance: Stat.convert_distance(max_stat.distance, distance_unit).round
      }
    end
  end
end
