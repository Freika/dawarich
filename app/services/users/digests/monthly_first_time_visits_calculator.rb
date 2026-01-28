# frozen_string_literal: true

module Users
  module Digests
    class MonthlyFirstTimeVisitsCalculator
      def initialize(user, year, month)
        @user = user
        @year = year.to_i
        @month = month.to_i
      end

      def call
        {
          'countries' => first_time_countries,
          'cities' => first_time_cities
        }
      end

      private

      attr_reader :user, :year, :month

      def previous_stats
        # All stats before current month (including previous years)
        @previous_stats ||= user.stats.where(
          'year < ? OR (year = ? AND month < ?)',
          year, year, month
        )
      end

      def current_stat
        @current_stat ||= user.stats.find_by(year: year, month: month)
      end

      def previous_countries
        @previous_countries ||= extract_countries(previous_stats)
      end

      def previous_cities
        @previous_cities ||= extract_cities(previous_stats)
      end

      def current_countries
        @current_countries ||= current_stat ? extract_countries([current_stat]) : []
      end

      def current_cities
        @current_cities ||= current_stat ? extract_cities([current_stat]) : []
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

          toponyms.filter_map { |t| t['country'] if t.is_a?(Hash) && t['country'].present? }
        end.uniq
      end

      def extract_cities(stats)
        stats.flat_map do |stat|
          toponyms = stat.toponyms
          next [] unless toponyms.is_a?(Array)

          toponyms.flat_map do |t|
            next [] unless t.is_a?(Hash) && t['cities'].is_a?(Array)

            t['cities'].filter_map { |c| c['city'] if c.is_a?(Hash) && c['city'].present? }
          end
        end.uniq
      end
    end
  end
end
