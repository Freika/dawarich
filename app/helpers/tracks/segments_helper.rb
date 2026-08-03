# frozen_string_literal: true

module Tracks::SegmentsHelper
  def modes_for_segment(segment, user)
    settings = (current_user == user && current_user_safe_settings) || user.safe_settings
    enabled = settings.enabled_transportation_modes
    current_mode = segment.transportation_mode.to_s

    options = enabled.map { |mode| [I18n.t("transportation_modes.#{mode}"), mode] }
    return options if enabled.include?(current_mode)

    options.unshift([
                      I18n.t('helpers.tracks.segments.mode_disabled',
                             mode: I18n.t("transportation_modes.#{current_mode}")),
                      current_mode
                    ])
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
    case current_user_safe_settings&.distance_unit
    when 'mi'
      I18n.t('units.miles', value: (distance_km * 0.621371).round(2))
    else
      I18n.t('units.kilometers', value: distance_km.round(2))
    end
  end

  def segment_duration(segment)
    return '-' unless segment.duration

    minutes = segment.duration / 60
    return I18n.t('units.minutes', value: minutes) if minutes < 60

    I18n.t('units.hours_minutes_compact', hours: minutes / 60, minutes: minutes % 60)
  end
end
