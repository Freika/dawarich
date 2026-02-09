# frozen_string_literal: true

module Maps
  class HexagonRequestHandler
    def initialize(params:, user: nil, stat: nil, start_date: nil, end_date: nil)
      @params = params
      @user = user
      @stat = stat
      @start_date = start_date
      @end_date = end_date
    end

    def call
      # For authenticated users, we need to find the matching stat
      stat ||= find_matching_stat

      if stat
        cached_result = Maps::HexagonCenterManager.new(stat:, user:).call

        return cached_result[:data] if cached_result&.dig(:success)
      end

      # No pre-calculated data available - return empty feature collection
      Rails.logger.debug 'No pre-calculated hexagon centers available'
      empty_feature_collection
    end

    private

    attr_reader :params, :user, :stat, :start_date, :end_date

    def find_matching_stat
      return unless user && start_date

      # Parse the date to extract year and month using user's timezone
      timezone = user.timezone
      date = if start_date.is_a?(String)
               Date.parse(start_date)
             elsif start_date.is_a?(Time)
               start_date.in_time_zone(timezone).to_date
             elsif start_date.is_a?(Integer)
               TimezoneHelper.timestamp_to_date(start_date, timezone)
             else
               return
             end

      # Find the stat for this user, year, and month
      user.stats.find_by(year: date.year, month: date.month)
    rescue Date::Error
      nil
    end

    def empty_feature_collection
      {
        'type' => 'FeatureCollection',
        'features' => [],
        'metadata' => {
          'hexagon_count' => 0,
          'total_points' => 0,
          'source' => 'pre_calculated'
        }
      }
    end
  end
end
