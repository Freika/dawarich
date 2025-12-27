# frozen_string_literal: true

module Users
  module Digests
    class CalculateYear
      def initialize(user_id, year)
        @user = ::User.find(user_id)
        @year = year.to_i
      end

      def call
        return nil if monthly_stats.empty?

        digest = Users::Digest.find_or_initialize_by(user: user, year: year, period_type: :yearly)

        digest.assign_attributes(
          distance: total_distance,
          toponyms: aggregate_toponyms,
          monthly_distances: build_monthly_distances,
          time_spent_by_location: calculate_time_spent,
          first_time_visits: calculate_first_time_visits,
          year_over_year: calculate_yoy_comparison,
          all_time_stats: calculate_all_time_stats
        )

        digest.save!
        digest
      end

      private

      attr_reader :user, :year

      def monthly_stats
        @monthly_stats ||= user.stats.where(year: year).order(:month)
      end

      def total_distance
        monthly_stats.sum(:distance)
      end

      def aggregate_toponyms
        countries = []
        cities = []

        monthly_stats.each do |stat|
          toponyms = stat.toponyms
          next unless toponyms.is_a?(Array)

          toponyms.each do |toponym|
            next unless toponym.is_a?(Hash)

            countries << toponym['country'] if toponym['country'].present?

            next unless toponym['cities'].is_a?(Array)

            toponym['cities'].each do |city|
              cities << city['city'] if city.is_a?(Hash) && city['city'].present?
            end
          end
        end

        {
          'countries' => countries.uniq.compact.sort,
          'cities' => cities.uniq.compact.sort
        }
      end

      def build_monthly_distances
        result = {}

        monthly_stats.each do |stat|
          result[stat.month.to_s] = stat.distance
        end

        # Fill in missing months with 0
        (1..12).each do |month|
          result[month.to_s] ||= 0
        end

        result
      end

      def calculate_time_spent
        country_time = Hash.new(0)
        city_time = Hash.new(0)

        monthly_stats.each do |stat|
          toponyms = stat.toponyms
          next unless toponyms.is_a?(Array)

          toponyms.each do |toponym|
            next unless toponym.is_a?(Hash)

            country = toponym['country']
            next unless toponym['cities'].is_a?(Array)

            toponym['cities'].each do |city|
              next unless city.is_a?(Hash)

              stayed_for = city['stayed_for'].to_i
              city_name = city['city']

              country_time[country] += stayed_for if country.present?
              city_time[city_name] += stayed_for if city_name.present?
            end
          end
        end

        {
          'countries' => country_time.sort_by { |_, v| -v }.first(10).map { |name, minutes| { 'name' => name, 'minutes' => minutes } },
          'cities' => city_time.sort_by { |_, v| -v }.first(10).map { |name, minutes| { 'name' => name, 'minutes' => minutes } }
        }
      end

      def calculate_first_time_visits
        FirstTimeVisitsCalculator.new(user, year).call
      end

      def calculate_yoy_comparison
        YearOverYearCalculator.new(user, year).call
      end

      def calculate_all_time_stats
        {
          'total_countries' => user.countries_visited.count,
          'total_cities' => user.cities_visited.count,
          'total_distance' => user.stats.sum(:distance)
        }
      end
    end
  end
end
