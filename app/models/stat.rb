# frozen_string_literal: true

class Stat < ApplicationRecord
  include DistanceConvertible

  validates :year, :month, presence: true

  belongs_to :user

  before_create :generate_sharing_uuid

  def distance_by_day
    monthly_points = points
    calculate_daily_distances(monthly_points)
  end

  def self.year_distance(year, user)
    stats_by_month = where(year:, user:).order(:month).index_by(&:month)

    (1..12).map do |month|
      month_name = Date::MONTHNAMES[month]
      distance = stats_by_month[month]&.distance || 0

      [month_name, distance]
    end
  end

  def points
    user.points
        .without_raw_data
        .where(timestamp: timespan)
        .order(timestamp: :asc)
  end

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

  def hexagons_available?
    h3_hex_ids.present? &&
      (h3_hex_ids.is_a?(Hash) || h3_hex_ids.is_a?(Array)) &&
      h3_hex_ids.any?
  end

  def generate_new_sharing_uuid!
    update!(sharing_uuid: SecureRandom.uuid)
  end

  def enable_sharing!(expiration: '1h')
    # Default to 24h if an invalid expiration is provided
    expiration = '24h' unless %w[1h 12h 24h 1w 1m].include?(expiration)

    expires_at = case expiration
                 when '1h' then 1.hour.from_now
                 when '12h' then 12.hours.from_now
                 when '24h' then 24.hours.from_now
                 when '1w' then 1.week.from_now
                 when '1m' then 1.month.from_now
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

  def calculate_data_bounds
    start_date = Date.new(year, month, 1).beginning_of_day
    end_date = start_date.end_of_month.end_of_day

    points_relation = user.points.where(timestamp: start_date.to_i..end_date.to_i)
    point_count = points_relation.count

    return nil if point_count.zero?

    bounds_result = ActiveRecord::Base.connection.exec_query(
      "SELECT MIN(ST_Y(lonlat::geometry)) as min_lat, MAX(ST_Y(lonlat::geometry)) as max_lat,
              MIN(ST_X(lonlat::geometry)) as min_lng, MAX(ST_X(lonlat::geometry)) as max_lng
       FROM points
       WHERE user_id = $1
       AND timestamp BETWEEN $2 AND $3
       AND lonlat IS NOT NULL",
      'data_bounds_query',
      [user.id, start_date.to_i, end_date.to_i]
    ).first

    {
      min_lat: bounds_result['min_lat'].to_f,
      max_lat: bounds_result['max_lat'].to_f,
      min_lng: bounds_result['min_lng'].to_f,
      max_lng: bounds_result['max_lng'].to_f,
      point_count: point_count
    }
  end

  def process!
    Stats::CalculatingJob.perform_later(user.id, year, month)
  end

  private

  def generate_sharing_uuid
    self.sharing_uuid ||= SecureRandom.uuid
  end

  def timespan
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end

  def calculate_daily_distances(monthly_points)
    Stats::DailyDistanceQuery.new(monthly_points, timespan, user_timezone).call
  end

  def user_timezone
    user.timezone.presence || Time.zone.name
  end
end
