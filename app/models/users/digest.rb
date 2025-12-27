# frozen_string_literal: true

class Users::Digest < ApplicationRecord
  self.table_name = 'digests'

  include DistanceConvertible

  EARTH_CIRCUMFERENCE_KM = 40_075
  MOON_DISTANCE_KM = 384_400

  belongs_to :user

  validates :year, presence: true
  validates :period_type, presence: true
  validates :year, uniqueness: { scope: %i[user_id period_type] }

  before_create :generate_sharing_uuid

  enum :period_type, { monthly: 0, yearly: 1 }

  # Sharing methods (following Stat model pattern)
  def sharing_enabled?
    sharing_settings.try(:[], 'enabled') == true
  end

  def sharing_expired?
    expiration = sharing_settings.try(:[], 'expiration')
    return false if expiration.blank?

    expires_at_value = sharing_settings.try(:[], 'expires_at')
    return true if expires_at_value.blank?

    expires_at = begin
      Time.zone.parse(expires_at_value)
    rescue StandardError
      nil
    end

    expires_at.present? ? Time.current > expires_at : true
  end

  def public_accessible?
    sharing_enabled? && !sharing_expired?
  end

  def generate_new_sharing_uuid!
    update!(sharing_uuid: SecureRandom.uuid)
  end

  def enable_sharing!(expiration: '24h')
    expiration = '24h' unless %w[1h 12h 24h].include?(expiration)

    expires_at = case expiration
                 when '1h' then 1.hour.from_now
                 when '12h' then 12.hours.from_now
                 when '24h' then 24.hours.from_now
                 end

    update!(
      sharing_settings: {
        'enabled' => true,
        'expiration' => expiration,
        'expires_at' => expires_at.iso8601
      },
      sharing_uuid: sharing_uuid || SecureRandom.uuid
    )
  end

  def disable_sharing!
    update!(
      sharing_settings: {
        'enabled' => false,
        'expiration' => nil,
        'expires_at' => nil
      }
    )
  end

  # Helper methods for accessing digest data
  # toponyms is an array like: [{'country' => 'Germany', 'cities' => [{'city' => 'Berlin'}]}]
  def countries_count
    return 0 unless toponyms.is_a?(Array)

    toponyms.count { |t| t['country'].present? }
  end

  def cities_count
    return 0 unless toponyms.is_a?(Array)

    toponyms.sum { |t| t['cities']&.count || 0 }
  end

  def first_time_countries
    first_time_visits['countries'] || []
  end

  def first_time_cities
    first_time_visits['cities'] || []
  end

  def top_countries_by_time
    time_spent_by_location['countries'] || []
  end

  def top_cities_by_time
    time_spent_by_location['cities'] || []
  end

  def yoy_distance_change
    year_over_year['distance_change_percent']
  end

  def yoy_countries_change
    year_over_year['countries_change']
  end

  def yoy_cities_change
    year_over_year['cities_change']
  end

  def previous_year
    year_over_year['previous_year']
  end

  def total_countries_all_time
    all_time_stats['total_countries'] || 0
  end

  def total_cities_all_time
    all_time_stats['total_cities'] || 0
  end

  def total_distance_all_time
    all_time_stats['total_distance'] || 0
  end

  def distance_km
    distance.to_f / 1000
  end

  def distance_comparison_text
    if distance_km >= MOON_DISTANCE_KM
      percentage = ((distance_km / MOON_DISTANCE_KM) * 100).round(1)
      "That's #{percentage}% of the distance to the Moon!"
    else
      percentage = ((distance_km / EARTH_CIRCUMFERENCE_KM) * 100).round(1)
      "That's #{percentage}% of Earth's circumference!"
    end
  end

  private

  def generate_sharing_uuid
    self.sharing_uuid ||= SecureRandom.uuid
  end
end
