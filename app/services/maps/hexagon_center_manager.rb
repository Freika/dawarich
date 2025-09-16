# frozen_string_literal: true

module Maps
  class HexagonCenterManager
    def self.call(stat:, target_user:)
      new(stat: stat, target_user: target_user).call
    end

    def initialize(stat:, target_user:)
      @stat = stat
      @target_user = target_user
    end

    def call
      return build_response_from_centers if pre_calculated_centers_available?
      return handle_legacy_area_too_large if legacy_area_too_large?

      nil # No pre-calculated data available
    end

    private

    attr_reader :stat, :target_user

    def pre_calculated_centers_available?
      return false unless stat&.hexagon_centers.present?

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

      # Trigger recalculation
      service = Stats::CalculateMonth.new(target_user.id, stat.year, stat.month)
      new_centers = service.send(:calculate_hexagon_centers)

      if new_centers && new_centers.is_a?(Array)
        stat.update(hexagon_centers: new_centers)
        result = build_hexagons_from_centers(new_centers)
        Rails.logger.debug "Successfully recalculated hexagon centers: #{new_centers.size} centers"
        return { success: true, data: result, pre_calculated: true }
      end

      nil # Recalculation failed or still too large
    end

    def build_hexagons_from_centers(centers)
      # Convert stored centers back to hexagon polygons
      # Each center is [lng, lat, earliest_timestamp, latest_timestamp]
      hexagon_features = centers.map.with_index do |center, index|
        lng, lat, earliest, latest = center

        # Generate hexagon polygon from center point (1000m hexagons)
        hexagon_geojson = Maps::HexagonPolygonGenerator.call(
          center_lng: lng,
          center_lat: lat,
          size_meters: 1000
        )

        {
          'type' => 'Feature',
          'id' => index + 1,
          'geometry' => hexagon_geojson,
          'properties' => {
            'hex_id' => index + 1,
            'hex_size' => 1000,
            'earliest_point' => earliest ? Time.zone.at(earliest).iso8601 : nil,
            'latest_point' => latest ? Time.zone.at(latest).iso8601 : nil
          }
        }
      end

      {
        'type' => 'FeatureCollection',
        'features' => hexagon_features,
        'metadata' => {
          'hex_size_m' => 1000,
          'count' => hexagon_features.count,
          'user_id' => target_user.id,
          'pre_calculated' => true
        }
      }
    end
  end
end
