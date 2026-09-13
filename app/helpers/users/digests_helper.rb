# frozen_string_literal: true

module Users
  module DigestsHelper
    PROGRESS_COLORS = %w[
      progress-primary progress-secondary progress-accent
      progress-info progress-success progress-warning
    ].freeze

    def progress_color_for_index(index)
      PROGRESS_COLORS[index % PROGRESS_COLORS.length]
    end

    def city_progress_value(city_count, max_cities)
      return 0 unless max_cities&.positive?

      (city_count.to_f / max_cities * 100).round
    end

    def max_cities_count(toponyms)
      return 0 if toponyms.blank?

      toponyms.map { |country| country['cities']&.length || 0 }.max
    end

    def distance_with_unit(distance_meters, unit)
      value = Users::Digest.convert_distance(distance_meters, unit).round
      I18n.t('helpers.users.digests.distance_with_unit', distance: number_with_delimiter(value), unit: unit)
    end

    def distance_comparison_text(distance_meters)
      distance_km = distance_meters.to_f / 1000

      if distance_km >= Users::Digest::MOON_DISTANCE_KM
        percentage = ((distance_km / Users::Digest::MOON_DISTANCE_KM) * 100).round(1)
        I18n.t('helpers.users.digests.moon_distance', percentage: percentage)
      else
        percentage = ((distance_km / Users::Digest::EARTH_CIRCUMFERENCE_KM) * 100).round(1)
        I18n.t('helpers.users.digests.earth_circumference', percentage: percentage)
      end
    end

    def format_time_spent(minutes)
      return I18n.t('units.minutes', value: minutes) if minutes < 60

      hours = minutes / 60
      remaining_minutes = minutes % 60

      if hours < 24
        I18n.t('units.hours_minutes_compact', hours: hours, minutes: remaining_minutes)
      else
        days = hours / 24
        remaining_hours = hours % 24
        I18n.t('units.days_hours_compact', days: days, hours: remaining_hours)
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
end
