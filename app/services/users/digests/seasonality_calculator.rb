# frozen_string_literal: true

module Users
  module Digests
    class SeasonalityCalculator
      NORTHERN_SEASONS = {
        'winter' => [12, 1, 2],
        'spring' => [3, 4, 5],
        'summer' => [6, 7, 8],
        'fall'   => [9, 10, 11]
      }.freeze

      SOUTHERN_SEASONS = {
        'winter' => [6, 7, 8],
        'spring' => [9, 10, 11],
        'summer' => [12, 1, 2],
        'fall'   => [3, 4, 5]
      }.freeze

      # Build a one-time lookup of IANA timezone identifier → latitude (Float).
      # TZInfo::Country.all covers ~400 named zones; we take the first latitude
      # seen for each identifier (multiple countries can share a zone).
      TIMEZONE_LATITUDES = begin
        TZInfo::Country.all.each_with_object({}) do |country, hash|
          country.zones.each do |zone|
            hash[zone.identifier] ||= zone.latitude.to_f
          end
        end.freeze
      rescue StandardError
        {}
      end

      def initialize(user, year)
        @user = user
        @year = year.to_i
      end

      def call
        distances_by_season = calculate_distances_by_season
        total = distances_by_season.values.sum

        return empty_result if total.zero?

        seasons.keys.index_with do |season|
          ((distances_by_season[season].to_f / total) * 100).round
        end
      end

      private

      attr_reader :user, :year

      def seasons
        southern_hemisphere? ? SOUTHERN_SEASONS : NORTHERN_SEASONS
      end

      def southern_hemisphere?
        tz_name = user.timezone.presence
        return false if tz_name.blank?

        latitude = TIMEZONE_LATITUDES[tz_name]
        latitude.present? && latitude < 0
      end

      def calculate_distances_by_season
        stats = user.stats.where(year: year)

        seasons.transform_values do |months|
          stats.where(month: months).sum(:distance)
        end
      end

      def empty_result
        { 'winter' => 0, 'spring' => 0, 'summer' => 0, 'fall' => 0 }
      end
    end
  end
end
