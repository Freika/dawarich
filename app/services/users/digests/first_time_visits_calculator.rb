# frozen_string_literal: true

module Users
  module Digests
    class FirstTimeVisitsCalculator
      def initialize(user, year)
        @user = user
        @year = year.to_i
      end

      def call
        {
          'countries' => first_time_countries,
          'cities' => first_time_cities
        }
      end

      private

      attr_reader :user, :year

      def previous_years_stats
        @previous_years_stats ||= user.stats.where('year < ?', year)
      end

      def current_year_stats
        @current_year_stats ||= user.stats.where(year: year)
      end

      def previous_countries
        @previous_countries ||= extract_countries(previous_years_stats)
      end

      def previous_cities
        @previous_cities ||= extract_cities(previous_years_stats)
      end

      def current_countries
        @current_countries ||= extract_countries(current_year_stats)
      end

      def current_cities
        @current_cities ||= extract_cities(current_year_stats)
      end

      def first_time_countries
        (current_countries - previous_countries).sort
      end

      def first_time_cities
        (current_cities - previous_cities).sort
      end

      def extract_countries(stats)
        stats.flat_map do |stat|
          toponyms = stat.toponyms
          next [] unless toponyms.is_a?(Array)

          toponyms.filter_map { |t| t['country'] if t.is_a?(Hash) }
        end.uniq.compact
      end

      def extract_cities(stats)
        stats.flat_map do |stat|
          toponyms = stat.toponyms
          next [] unless toponyms.is_a?(Array)

          toponyms.flat_map do |t|
            next [] unless t.is_a?(Hash) && t['cities'].is_a?(Array)

            t['cities'].filter_map { |c| c['city'] if c.is_a?(Hash) }
          end
        end.uniq.compact
      end
    end
  end
end
