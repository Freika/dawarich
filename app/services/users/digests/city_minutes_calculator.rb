# frozen_string_literal: true

module Users
  module Digests
    class CityMinutesCalculator
      TOP_CITIES_LIMIT = 10

      def initialize(toponyms)
        @toponyms = toponyms
      end

      def call(limit = TOP_CITIES_LIMIT)
        minutes_by_city
          .sort_by { |_, minutes| -minutes }
          .first(limit)
          .map { |name, minutes| { 'name' => name, 'minutes' => minutes } }
      end

      private

      attr_reader :toponyms

      def minutes_by_city
        city_time = Hash.new(0)
        return city_time unless toponyms.is_a?(Array)

        toponyms.each do |toponym|
          next unless toponym.is_a?(Hash)
          next unless toponym['cities'].is_a?(Array)

          accumulate_cities(toponym['cities'], city_time)
        end

        city_time
      end

      def accumulate_cities(cities, city_time)
        cities.each do |city|
          next unless city.is_a?(Hash)

          city_name = city['city']
          city_time[city_name] += city['stayed_for'].to_i if city_name.present?
        end
      end
    end
  end
end
