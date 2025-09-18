# frozen_string_literal: true

module Maps
  class HexagonRequestHandler
    def initialize(params:, user: nil, context: nil)
      @params = params
      @user = user
      @context = context
    end

    def call
      context = @context || resolve_context

      # For authenticated users, we need to find the matching stat
      stat = context[:stat] || find_matching_stat(context)

      # Use pre-calculated hexagon centers
      if stat
        cached_result = Maps::HexagonCenterManager.call(
          stat: stat,
          user: context[:user]
        )

        return cached_result[:data] if cached_result&.dig(:success)
      end

      # No pre-calculated data available - return empty feature collection
      Rails.logger.debug 'No pre-calculated hexagon centers available'
      empty_feature_collection
    end

    private

    attr_reader :params, :user, :context

    def find_matching_stat(context)
      return unless context[:user] && context[:start_date]

      # Parse the date to extract year and month
      if context[:start_date].is_a?(String)
        date = Date.parse(context[:start_date])
      elsif context[:start_date].is_a?(Time)
        date = context[:start_date].to_date
      else
        return
      end

      # Find the stat for this user, year, and month
      context[:user].stats.find_by(year: date.year, month: date.month)
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
