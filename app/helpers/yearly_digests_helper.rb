# frozen_string_literal: true

module YearlyDigestsHelper
  EARTH_CIRCUMFERENCE_KM = 40_075
  MOON_DISTANCE_KM = 384_400

  def distance_with_unit(distance_meters, unit)
    value = YearlyDigest.convert_distance(distance_meters, unit).round
    "#{number_with_delimiter(value)} #{unit}"
  end

  def distance_comparison_text(distance_meters)
    distance_km = distance_meters.to_f / 1000

    if distance_km >= MOON_DISTANCE_KM
      percentage = ((distance_km / MOON_DISTANCE_KM) * 100).round(1)
      "That's #{percentage}% of the distance to the Moon!"
    else
      percentage = ((distance_km / EARTH_CIRCUMFERENCE_KM) * 100).round(1)
      "That's #{percentage}% of Earth's circumference!"
    end
  end

  def format_time_spent(minutes)
    return "#{minutes} minutes" if minutes < 60

    hours = minutes / 60
    remaining_minutes = minutes % 60

    if hours < 24
      "#{hours}h #{remaining_minutes}m"
    else
      days = hours / 24
      remaining_hours = hours % 24
      "#{days}d #{remaining_hours}h"
    end
  end

  def yoy_change_class(change)
    return '' if change.nil?

    change.negative? ? 'negative' : 'positive'
  end

  def yoy_change_text(change)
    return '' if change.nil?

    prefix = change.positive? ? '+' : ''
    "#{prefix}#{change}%"
  end
end
