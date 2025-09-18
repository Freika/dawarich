# frozen_string_literal: true

module Maps
  class H3HexagonRenderer
    def initialize(params:, user: nil)
      @params = params
      @user = user
    end

    def call
      context = resolve_context
      h3_data = get_h3_hexagon_data(context)

      return empty_feature_collection if h3_data.empty?

      convert_h3_to_geojson(h3_data)
    end

    private

    attr_reader :params, :user

    def resolve_context
      Maps::HexagonContextResolver.call(
        params: params,
        user: user
      )
    end

    def get_h3_hexagon_data(context)
      # For public sharing, get pre-calculated data from stat
      if context[:stat]&.hexagon_centers.present?
        hexagon_data = context[:stat].hexagon_centers

        # Check if this is old format (coordinates) or new format (H3 indexes)
        if hexagon_data.first.is_a?(Array) && hexagon_data.first[0].is_a?(Float)
          Rails.logger.debug "Found old coordinate format for stat #{context[:stat].id}, generating H3 on-the-fly"
          return generate_h3_data_on_the_fly(context)
        else
          Rails.logger.debug "Using pre-calculated H3 data for stat #{context[:stat].id}"
          return hexagon_data
        end
      end

      # For authenticated users, calculate on-the-fly if no pre-calculated data
      Rails.logger.debug 'No pre-calculated H3 data, calculating on-the-fly'
      generate_h3_data_on_the_fly(context)
    end

    def generate_h3_data_on_the_fly(context)
      start_date = parse_date_for_h3(context[:start_date])
      end_date = parse_date_for_h3(context[:end_date])
      h3_resolution = params[:h3_resolution]&.to_i&.clamp(0, 15) || 6

      Maps::H3HexagonCenters.new(
        user_id: context[:target_user]&.id,
        start_date: start_date,
        end_date: end_date,
        h3_resolution: h3_resolution
      ).call
    end

    def convert_h3_to_geojson(h3_data)
      features = h3_data.map do |h3_record|
        h3_index_string, point_count, earliest_timestamp, latest_timestamp = h3_record

        # Convert hex string back to H3 index
        h3_index = h3_index_string.to_i(16)

        # Get hexagon boundary coordinates
        boundary_coordinates = H3.to_boundary(h3_index)

        # Convert to GeoJSON polygon format (lng, lat)
        polygon_coordinates = boundary_coordinates.map { |lat, lng| [lng, lat] }
        polygon_coordinates << polygon_coordinates.first # Close the polygon

        {
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [polygon_coordinates]
          },
          properties: {
            h3_index: h3_index_string,
            point_count: point_count,
            earliest_point: earliest_timestamp ? Time.at(earliest_timestamp).iso8601 : nil,
            latest_point: latest_timestamp ? Time.at(latest_timestamp).iso8601 : nil,
            center: H3.to_geo_coordinates(h3_index) # [lat, lng]
          }
        }
      end

      {
        type: 'FeatureCollection',
        features: features,
        metadata: {
          hexagon_count: features.size,
          total_points: features.sum { |f| f[:properties][:point_count] },
          source: 'h3'
        }
      }
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

    def parse_date_for_h3(date_param)
      # If already a Time object (from public sharing context), return as-is
      return date_param if date_param.is_a?(Time)

      # If it's a string ISO date, parse it directly to Time
      return Time.zone.parse(date_param) if date_param.is_a?(String)

      # If it's an integer timestamp, convert to Time
      return Time.zone.at(date_param) if date_param.is_a?(Integer)

      # For other cases, try coercing and converting
      timestamp = Maps::DateParameterCoercer.new(date_param).call
      Time.zone.at(timestamp)
    end
  end
end
