# frozen_string_literal: true

class Overland::Params
  attr_reader :data, :points

  def initialize(json)
    @data = normalize(json)
    @points = Array.wrap(@data[:locations])
  end

  def call
    return [] if points.blank?

    points.map do |point|
      next if point[:geometry].nil? || point.dig(:properties, :timestamp).nil?

      {
        lonlat:             lonlat(point),
        battery_status:     point[:properties][:battery_state],
        battery:            battery_level(point[:properties][:battery_level]),
        timestamp:          DateTime.parse(point[:properties][:timestamp]),
        altitude:           point[:properties][:altitude],
        velocity:           point[:properties][:speed],
        tracker_id:         point[:properties][:device_id],
        ssid:               point[:properties][:wifi],
        accuracy:           point[:properties][:horizontal_accuracy],
        vertical_accuracy:  point[:properties][:vertical_accuracy],
        motion_data:        Points::MotionDataExtractor.from_overland_properties(point[:properties]),
        raw_data:           {}
      }
    end.compact
  end

  private

  def battery_level(level)
    value = (level.to_f * 100).to_i

    value.positive? ? value : nil
  end

  def lonlat(point)
    coordinates = point.dig(:geometry, :coordinates)
    return if coordinates.blank?

    "POINT(#{coordinates[0]} #{coordinates[1]})"
  end

  def normalize(json)
    payload = case json
              when ActionController::Parameters
                json.to_unsafe_h
              when Hash
                json
              when Array
                { locations: json }
              else
                json.respond_to?(:to_h) ? json.to_h : {}
              end

    payload.with_indifferent_access
  end
end
