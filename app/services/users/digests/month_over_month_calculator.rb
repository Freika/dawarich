# frozen_string_literal: true

module Users
  module Digests
    class MonthOverMonthCalculator
      def initialize(user, year, month)
        @user = user
        @year = year.to_i
        @month = month.to_i
      end

      def call
        return {} if previous_month_stat.blank?

        {
          'previous_year' => prev_year,
          'previous_month' => prev_month,
          'distance_change_percent' => calculate_distance_change_percent,
          'countries_change' => calculate_countries_change,
          'cities_change' => calculate_cities_change
        }.compact
      end

      private

      attr_reader :user, :year, :month

      def prev_year
        month == 1 ? year - 1 : year
      end

      def prev_month
        month == 1 ? 12 : month - 1
      end

      def previous_month_stat
        @previous_month_stat ||= user.stats.find_by(year: prev_year, month: prev_month)
      end

      def current_month_stat
        @current_month_stat ||= user.stats.find_by(year: year, month: month)
      end

      def calculate_distance_change_percent
        prev_distance = previous_month_stat&.distance || 0
        return nil if prev_distance.zero?

        curr_distance = current_month_stat&.distance || 0
        ((curr_distance - prev_distance).to_f / prev_distance * 100).round
      end

      def calculate_countries_change
        prev_count = count_countries(previous_month_stat)
        curr_count = count_countries(current_month_stat)

        curr_count - prev_count
      end

      def calculate_cities_change
        prev_count = count_cities(previous_month_stat)
        curr_count = count_cities(current_month_stat)

        curr_count - prev_count
      end

      def count_countries(stat)
        return 0 unless stat

        toponyms = stat.toponyms
        return 0 unless toponyms.is_a?(Array)

        toponyms.filter_map { |t| t['country'] if t.is_a?(Hash) && t['country'].present? }.uniq.count
      end

      def count_cities(stat)
        return 0 unless stat

        toponyms = stat.toponyms
        return 0 unless toponyms.is_a?(Array)

        toponyms.flat_map do |t|
          next [] unless t.is_a?(Hash) && t['cities'].is_a?(Array)

          t['cities'].filter_map { |c| c['city'] if c.is_a?(Hash) && c['city'].present? }
        end.uniq.count
      end
    end
  end
end
