# frozen_string_literal: true

# Normalizes the JSON payload sent by the Dawarich mobile client (a Traccar-style
# tracker built on react-native-background-geolocation) into a point hash.
class Traccar::Params
  attr_reader :payload

  def initialize(payload)
    @payload = normalize(payload)
  end

  def call
    return unless valid?

    lon = parse_coordinate(location[:longitude], -180.0, 180.0)
    lat = parse_coordinate(location[:latitude], -90.0, 90.0)
    return if lon.nil? || lat.nil?

    parsed_timestamp = parse_timestamp(location[:timestamp])
    return if parsed_timestamp.nil?

    altitude_value = location[:altitude]

    attrs = {
      lonlat:         "POINT(#{lon} #{lat})",
      timestamp:      parsed_timestamp,
      altitude:       altitude_value,
      accuracy:       location[:accuracy],
      velocity:       location[:speed]&.to_s,
      tracker_id:     payload[:device_id],
      battery:        battery_level,
      battery_status: battery_status,
      motion_data:    Points::MotionDataExtractor.from_traccar(payload),
      raw_data:       payload.deep_stringify_keys
    }
    attrs[:altitude_decimal] = altitude_value if Point.column_names.include?('altitude_decimal')
    attrs
  end

  private

  def valid?
    location.present? &&
      location[:latitude].present? &&
      location[:longitude].present? &&
      location[:timestamp].present?
  end

  def parse_coordinate(raw, min, max)
    value = Float(raw.to_s)
    return nil unless value.finite?
    return nil if value < min || value > max

    value
  rescue ArgumentError, TypeError
    nil
  end

  def parse_timestamp(value)
    DateTime.parse(value.to_s).to_i
  rescue ArgumentError, TypeError
    nil
  end

  def location
    @location ||= payload[:location] || {}
  end

  def battery
    @battery ||= payload[:battery] || {}
  end

  def battery_level
    level = battery[:level]
    return nil if level.nil?

    value = (level.to_f * 100).to_i
    value.positive? ? value : nil
  end

  def battery_status
    return 'unknown' unless battery.key?(:is_charging)

    battery[:is_charging] ? 'charging' : 'unplugged'
  end

  def normalize(input)
    hash = case input
           when ActionController::Parameters then input.to_unsafe_h
           when Hash then input
           else input.respond_to?(:to_h) ? input.to_h : {}
           end

    hash.deep_symbolize_keys
  end
end
