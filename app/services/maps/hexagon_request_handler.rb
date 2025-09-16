# frozen_string_literal: true

module Maps
  class HexagonRequestHandler
    def self.call(params:, current_api_user: nil)
      new(params: params, current_api_user: current_api_user).call
    end

    def initialize(params:, current_api_user: nil)
      @params = params
      @current_api_user = current_api_user
    end

    def call
      context = resolve_context

      # Try to use pre-calculated hexagon centers first
      if context[:stat]
        cached_result = Maps::HexagonCenterManager.call(
          stat: context[:stat],
          target_user: context[:target_user]
        )

        return cached_result[:data] if cached_result&.dig(:success)
      end

      # Fall back to on-the-fly calculation
      Rails.logger.debug 'No pre-calculated data available, calculating hexagons on-the-fly'
      generate_hexagons_on_the_fly(context)
    end

    private

    attr_reader :params, :current_api_user

    def resolve_context
      Maps::HexagonContextResolver.call(
        params: params,
        current_api_user: current_api_user
      )
    end

    def generate_hexagons_on_the_fly(context)
      # Parse dates for H3 calculator which expects Time objects
      start_date = parse_date_for_h3(context[:start_date])
      end_date = parse_date_for_h3(context[:end_date])

      result = Maps::H3HexagonCalculator.new(
        context[:target_user]&.id,
        start_date,
        end_date,
        h3_resolution
      ).call

      return result[:data] if result[:success]

      # If H3 calculation fails, log error and return empty feature collection
      Rails.logger.error "H3 calculation failed: #{result[:error]}"
      empty_feature_collection
    end

    def empty_feature_collection
      {
        type: 'FeatureCollection',
        features: [],
        metadata: {
          hexagon_count: 0,
          total_points: 0,
          source: 'h3'
        }
      }
    end

    def h3_resolution
      # Allow custom resolution via parameter, default to 8
      resolution = params[:h3_resolution]&.to_i || 8

      # Clamp to valid H3 resolution range (0-15)
      resolution.clamp(0, 15)
    end

    def parse_date_for_h3(date_param)
      # If already a Time object (from public sharing context), return as-is
      return date_param if date_param.is_a?(Time)

      # If it's a string ISO date, parse it directly to Time
      return Time.parse(date_param) if date_param.is_a?(String)

      # If it's an integer timestamp, convert to Time
      return Time.at(date_param) if date_param.is_a?(Integer)

      # For other cases, try coercing and converting
      timestamp = Maps::DateParameterCoercer.call(date_param)
      Time.at(timestamp)
    end
  end
end
