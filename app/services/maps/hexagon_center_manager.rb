# frozen_string_literal: true

module Maps
  class HexagonCenterManager
    def initialize(stat:, user:)
      @stat = stat
      @user = user
    end

    def call
      return build_response_from_centers if pre_calculated_centers_available?

      nil # No pre-calculated data available
    end

    private

    attr_reader :stat, :user

    def pre_calculated_centers_available?
      return false if stat&.h3_hex_ids.blank?

      stat.h3_hex_ids.is_a?(Hash) && stat.h3_hex_ids.any?
    end

    def build_response_from_centers
      hex_ids = stat.h3_hex_ids
      Rails.logger.debug "Using pre-calculated H3 hex IDs: #{hex_ids.size} hexagons"

      result = build_hexagons_from_h3_ids(hex_ids)
      { success: true, data: result, pre_calculated: true }
    end

    def recalculate_h3_hex_ids
      service = Stats::CalculateMonth.new(user.id, stat.year, stat.month)
      service.send(:calculate_h3_hex_ids)
    end

    def update_stat_with_new_hex_ids(new_hex_ids)
      stat.update(h3_hex_ids: new_hex_ids)
      result = build_hexagons_from_h3_ids(new_hex_ids)
      Rails.logger.debug "Successfully recalculated H3 hex IDs: #{new_hex_ids.size} hexagons"
      { success: true, data: result, pre_calculated: true }
    end

    def build_hexagons_from_h3_ids(hex_ids)
      # Convert stored H3 IDs back to hexagon polygons
      hexagon_features = hex_ids.map.with_index do |(h3_index, data), index|
        build_hexagon_feature_from_h3(h3_index, data, index)
      end

      build_feature_collection(hexagon_features)
    end

    def build_hexagon_feature_from_h3(h3_index, data, index)
      count, earliest, latest = data

      {
        'type' => 'Feature',
        'id' => index + 1,
        'geometry' => generate_hexagon_geometry_from_h3(h3_index),
        'properties' => build_hexagon_properties(index, count, earliest, latest)
      }
    end

    def generate_hexagon_geometry_from_h3(h3_index)
      Maps::HexagonPolygonGenerator.new(h3_index: h3_index).call
    end

    def build_hexagon_properties(index, count, earliest, latest)
      {
        'hex_id' => index + 1,
        'point_count' => count,
        'earliest_point' => earliest ? Time.zone.at(earliest).iso8601 : nil,
        'latest_point' => latest ? Time.zone.at(latest).iso8601 : nil
      }
    end

    def build_feature_collection(hexagon_features)
      {
        'type' => 'FeatureCollection',
        'features' => hexagon_features,
        'metadata' => {
          'count' => hexagon_features.count,
          'user_id' => user.id,
          'pre_calculated' => true
        }
      }
    end
  end
end
