# frozen_string_literal: true

# Normalizes JSON and latitude/longitude form payloads from Traccar trackers.
# Supports both the flat Dawarich mobile client shape (coords directly on
# `location`, `battery`/`activity` at the top level) and the nested upstream
# traccar-client shape (coords under `location.coords`, `battery`/`activity`
# under `location`).
class Traccar::Params
  attr_reader :payload, :raw_payload

  def initialize(payload)
    @raw_payload = normalize(payload)
    @payload = normalize_protocol(raw_payload)
  end

  def call
    return unless valid?

    lon = parse_coordinate(coords[:longitude], -180.0, 180.0)
    lat = parse_coordinate(coords[:latitude], -90.0, 90.0)
    return if lon.nil? || lat.nil?

    parsed_timestamp = parse_timestamp(location[:timestamp])
    return if parsed_timestamp.nil?

    altitude_value = coords[:altitude]

    attrs = {
      lonlat:         "POINT(#{lon} #{lat})",
      timestamp:      parsed_timestamp,
      altitude:       altitude_value,
      accuracy:       coords[:accuracy],
      velocity:       coords[:speed]&.to_s,
      tracker_id:     payload[:device_id],
      battery:        battery_level,
      battery_status: battery_status,
      motion_data:    Points::MotionDataExtractor.from_traccar(payload),
      raw_data:       raw_payload.deep_stringify_keys
    }
    attrs[:altitude_decimal] = altitude_value if Point.column_names.include?('altitude_decimal')
    attrs
  end

  private

  def valid?
    coords.present? &&
      coords[:latitude].present? &&
      coords[:longitude].present? &&
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
    if value.to_s.match?(/\A\d+\z/)
      numeric = Integer(value.to_s, 10)
      return numeric > 10_000_000_000 ? numeric / 1000 : numeric
    end

    DateTime.parse(value.to_s).to_i
  rescue ArgumentError, TypeError
    nil
  end

  def location
    @location ||= payload[:location] || {}
  end

  def coords
    @coords ||= location[:coords].presence || location
  end

  def battery
    @battery ||= location[:battery].presence || payload[:battery] || {}
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

  def normalize_protocol(input)
    return input unless input[:location].blank? && input[:lat].present? && input[:lon].present?

    {
      device_id: input[:id],
      location: {
        timestamp: input[:timestamp],
        latitude: input[:lat],
        longitude: input[:lon],
        accuracy: input[:accuracy],
        altitude: input[:altitude],
        speed: input[:speed].present? ? input[:speed].to_f / 1.94384 : nil,
        heading: input[:bearing],
        event: input[:alarm]
      },
      battery: {
        level: input[:batt].present? ? input[:batt].to_f / 100 : nil,
        is_charging: ActiveModel::Type::Boolean.new.cast(input[:charge])
      }.compact
    }
  end
end
