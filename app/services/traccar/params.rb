# frozen_string_literal: true

# Normalizes a Traccar Client v9+ JSON payload into Dawarich's point hash.
# Payload reference: https://www.traccar.org/osmand/
class Traccar::Params
  attr_reader :payload

  def initialize(payload)
    @payload = normalize(payload)
  end

  def call
    return unless valid?

    {
      lonlat:         "POINT(#{location[:longitude]} #{location[:latitude]})",
      timestamp:      DateTime.parse(location[:timestamp].to_s).to_i,
      altitude:       location[:altitude],
      accuracy:       location[:accuracy],
      velocity:       location[:speed]&.to_s,
      tracker_id:     payload[:device_id],
      battery:        battery_level,
      battery_status: battery_status,
      motion_data:    motion_data,
      raw_data:       payload.deep_stringify_keys
    }
  end

  private

  def valid?
    location.present? &&
      location[:latitude].present? &&
      location[:longitude].present? &&
      location[:timestamp].present?
  end

  def location
    @location ||= payload[:location] || {}
  end

  def battery
    @battery ||= payload[:battery] || {}
  end

  def activity
    @activity ||= payload[:activity] || {}
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

  def motion_data
    data = {}
    data['activity']  = activity[:type] if activity[:type]
    data['is_moving'] = location[:is_moving] unless location[:is_moving].nil?
    data['event']     = location[:event] if location[:event]
    data
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
