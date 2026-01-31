# frozen_string_literal: true

module Users
  module Digests
    class SeasonalityCalculator
      # Northern hemisphere seasons by month
      SEASONS = {
        'winter' => [12, 1, 2],
        'spring' => [3, 4, 5],
        'summer' => [6, 7, 8],
        'fall' => [9, 10, 11]
      }.freeze

      def initialize(user, year)
        @user = user
        @year = year.to_i
      end

      def call
        distances_by_season = calculate_distances_by_season
        total = distances_by_season.values.sum

        return empty_result if total.zero?

        SEASONS.keys.index_with do |season|
          ((distances_by_season[season].to_f / total) * 100).round
        end
      end

      private

      attr_reader :user, :year

      def calculate_distances_by_season
        stats = user.stats.where(year: year)

        SEASONS.transform_values do |months|
          stats.where(month: months).sum(:distance)
        end
      end

      def empty_result
        { 'winter' => 0, 'spring' => 0, 'summer' => 0, 'fall' => 0 }
      end
    end
  end
end
