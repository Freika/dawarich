# frozen_string_literal: true

module Maps
  class HexagonCenterManager
    def initialize(stat:, user:)
      @stat = stat
      @user = user
    end

    def call
      return build_response_from_centers if pre_calculated_centers_available?
      return handle_legacy_area_too_large if legacy_area_too_large?

      nil # No pre-calculated data available
    end

    private

    attr_reader :stat, :user

    def pre_calculated_centers_available?
      return false if stat&.hexagon_centers.blank?

      # Handle legacy hash format
      if stat.hexagon_centers.is_a?(Hash)
        !stat.hexagon_centers['area_too_large']
      else
        # Handle array format (actual hexagon centers)
        stat.hexagon_centers.is_a?(Array) && stat.hexagon_centers.any?
      end
    end

    def legacy_area_too_large?
      stat&.hexagon_centers.is_a?(Hash) && stat.hexagon_centers['area_too_large']
    end

    def build_response_from_centers
      centers = stat.hexagon_centers
      Rails.logger.debug "Using pre-calculated hexagon centers: #{centers.size} centers"

      result = build_hexagons_from_centers(centers)
      { success: true, data: result, pre_calculated: true }
    end

    def handle_legacy_area_too_large
      Rails.logger.info "Recalculating previously skipped large area hexagons for stat #{stat.id}"

      new_centers = recalculate_hexagon_centers
      return nil unless new_centers.is_a?(Array)

      update_stat_with_new_centers(new_centers)
    end

    def recalculate_hexagon_centers
      service = Stats::CalculateMonth.new(user.id, stat.year, stat.month)
      service.send(:calculate_hexagon_centers)
    end

    def update_stat_with_new_centers(new_centers)
      stat.update(hexagon_centers: new_centers)
      result = build_hexagons_from_centers(new_centers)
      Rails.logger.debug "Successfully recalculated hexagon centers: #{new_centers.size} centers"
      { success: true, data: result, pre_calculated: true }
    end

    def build_hexagons_from_centers(centers)
      # Convert stored centers back to hexagon polygons
      hexagon_features = centers.map.with_index { |center, index| build_hexagon_feature(center, index) }

      build_feature_collection(hexagon_features)
    end

    def build_hexagon_feature(center, index)
      lng, lat, earliest, latest = center

      {
        'type' => 'Feature',
        'id' => index + 1,
        'geometry' => generate_hexagon_geometry(lng, lat),
        'properties' => build_hexagon_properties(index, earliest, latest)
      }
    end

    def generate_hexagon_geometry(lng, lat)
      Maps::HexagonPolygonGenerator.new(
        center_lng: lng,
        center_lat: lat
      ).call
    end

    def build_hexagon_properties(index, earliest, latest)
      {
        'hex_id' => index + 1,
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
