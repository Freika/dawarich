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
    sharing_settings['enabled'] == true
  end

  def sharing_expired?
    return false unless sharing_settings['expiration']
    return false if sharing_settings['expiration'] == 'permanent'

    Time.current > sharing_settings['expires_at']
  end

  def public_accessible?
    sharing_enabled? && !sharing_expired?
  end

  def generate_new_sharing_uuid!
    update!(sharing_uuid: SecureRandom.uuid)
  end

  def enable_sharing!(expiration: '1h')
    expires_at = case expiration
                 when '1h'
                   1.hour.from_now
                 when '12h'
                   12.hours.from_now
                 when '24h'
                   24.hours.from_now
                 end

    update!(
      sharing_settings: {
        'enabled' => true,
        'expiration' => expiration,
        'expires_at' => expires_at&.iso8601
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
    # Future: Once user.timezone column exists, uncomment the line below
    # user.timezone.presence || Time.zone.name

    # For now, use application timezone
    Time.zone.name
  end
end
