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
      hexagon_params = build_hexagon_params(context)
      result = Maps::HexagonGrid.new(hexagon_params).call
      Rails.logger.debug "Hexagon service result: #{result['features']&.count || 0} features"
      result
    end

    def build_hexagon_params(context)
      bbox_params.merge(
        user_id: context[:target_user]&.id,
        start_date: context[:start_date],
        end_date: context[:end_date]
      )
    end

    def bbox_params
      params.permit(:min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :viewport_width, :viewport_height)
    end
  end
end