# frozen_string_literal: true

module Tracks::SegmentsHelper
  def modes_for_segment(segment, user)
    modes_for_mode(segment.transportation_mode, user)
  end

  # Same options list keyed off a bare mode string, for surfaces that hold a
  # derived leg rather than the segment record itself.
  def modes_for_mode(mode, user)
    settings = (current_user == user && current_user_safe_settings) || user.safe_settings
    enabled = settings.enabled_transportation_modes
    current_mode = mode.to_s

    options = enabled.map { |m| [I18n.t("transportation_modes.#{m}"), m] }
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

  # Lucide name for a mode, for surfaces that draw icons rather than emoji.
  # Emoji arrive as OS-supplied color bitmaps that ignore currentColor and
  # size inconsistently next to the rest of the icon set.
  # Motorcycle shares the bike glyph — lucide ships no motorcycle, and the
  # two never appear together without a verb to tell them apart.
  def mode_icon_name(mode)
    {
      'unknown' => 'route', 'stationary' => 'pause', 'walking' => 'footprints',
      'running' => 'activity', 'cycling' => 'bike', 'driving' => 'car',
      'bus' => 'bus', 'train' => 'train-front', 'flying' => 'plane',
      'boat' => 'ship', 'motorcycle' => 'bike'
    }[mode.to_s] || 'route'
  end

  def segment_distance(segment)
    display_distance_m(segment.distance)
  end

  def display_distance_m(meters)
    return '-' unless meters

    distance_km = meters / 1000.0
    case current_user_safe_settings&.distance_unit
    when 'mi'
      I18n.t('units.miles', value: (distance_km * 0.621371).round(2))
    else
      I18n.t('units.kilometers', value: distance_km.round(2))
    end
  end

  def mode_color(mode)
    Tracks::GeojsonSerializer::MODE_COLORS.fetch(mode.to_s, Tracks::GeojsonSerializer::MODE_COLORS['unknown'])
  end

  def segment_confidence_percent(segment)
    return nil unless segment.confidence_score

    (segment.confidence_score * 100).round
  end

  def segment_duration(segment)
    return '-' unless segment.duration

    minutes = segment.duration / 60
    return I18n.t('units.minutes', value: minutes) if minutes < 60

    I18n.t('units.hours_minutes_compact', hours: minutes / 60, minutes: minutes % 60)
  end
end
