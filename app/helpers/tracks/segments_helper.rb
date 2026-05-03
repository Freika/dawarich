# frozen_string_literal: true

module Tracks::SegmentsHelper
  def modes_for_segment(segment, user)
    safe_settings = Users::SafeSettings.new(user.settings || {})
    enabled = safe_settings.enabled_transportation_modes
    current_mode = segment.transportation_mode.to_s

    options = enabled.map { |m| [m.titleize, m] }
    return options if enabled.include?(current_mode)

    options.unshift(["#{current_mode.titleize} (disabled in settings)", current_mode])
  end

  def mode_emoji(mode)
    {
      'unknown' => '❓', 'stationary' => '🛑', 'walking' => '🚶',
      'running' => '🏃', 'cycling' => '🚴', 'driving' => '🚗',
      'bus' => '🚌', 'train' => '🚆', 'flying' => '✈️',
      'boat' => '⛵', 'motorcycle' => "\u{1F3CD}️"
    }[mode.to_s] || '❓'
  end

  def segment_distance(segment)
    return '-' unless segment.distance

    distance_km = segment.distance / 1000.0
    case current_user&.safe_settings&.distance_unit
    when 'mi'
      "#{(distance_km * 0.621371).round(2)} mi"
    else
      "#{distance_km.round(2)} km"
    end
  end

  def segment_duration(segment)
    return '-' unless segment.duration

    minutes = segment.duration / 60
    return "#{minutes} min" if minutes < 60

    "#{minutes / 60}h #{minutes % 60}m"
  end
end
