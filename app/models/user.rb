# frozen_string_literal: true

class User < ApplicationRecord # rubocop:disable Metrics/ClassLength
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  has_many :points, dependent: :destroy, counter_cache: true
  has_many :imports,        dependent: :destroy
  has_many :stats,          dependent: :destroy
  has_many :exports,        dependent: :destroy
  has_many :notifications,  dependent: :destroy
  has_many :areas,          dependent: :destroy
  has_many :visits,         dependent: :destroy
  has_many :places, through: :visits
  has_many :trips,  dependent: :destroy
  has_many :tracks, dependent: :destroy

  # Family associations
  has_one :family_membership, dependent: :destroy
  has_one :family, through: :family_membership
  has_one :created_family, class_name: 'Family', foreign_key: 'creator_id', inverse_of: :creator, dependent: :destroy
  has_many :sent_family_invitations, class_name: 'FamilyInvitation', foreign_key: 'invited_by_id',
inverse_of: :invited_by, dependent: :destroy

  after_create :create_api_key
  after_commit :activate, on: :create, if: -> { DawarichSettings.self_hosted? }
  after_commit :start_trial, on: :create, if: -> { !DawarichSettings.self_hosted? }

  before_save :sanitize_input

  before_destroy :check_family_ownership

  validates :email, presence: true
  validates :reset_password_token, uniqueness: true, allow_nil: true

  attribute :admin, :boolean, default: false
  attribute :points_count, :integer, default: 0

  scope :active_or_trial, -> { where(status: %i[active trial]) }

  enum :status, { inactive: 0, active: 1, trial: 2 }

  def safe_settings
    Users::SafeSettings.new(settings)
  end

  def countries_visited
    Rails.cache.fetch("dawarich/user_#{id}_countries_visited", expires_in: 1.day) do
      points
        .without_raw_data
        .where.not(country_name: [nil, ''])
        .distinct
        .pluck(:country_name)
        .compact
    end
  end

  def cities_visited
    Rails.cache.fetch("dawarich/user_#{id}_cities_visited", expires_in: 1.day) do
      points.where.not(city: [nil, '']).distinct.pluck(:city).compact
    end
  end

  def total_distance
    total_distance_meters = stats.sum(:distance)
    Stat.convert_distance(total_distance_meters, safe_settings.distance_unit)
  end

  def total_countries
    countries_visited.size
  end

  def total_cities
    cities_visited.size
  end

  def total_reverse_geocoded_points
    points.where.not(reverse_geocoded_at: nil).count
  end

  def total_reverse_geocoded_points_without_data
    points.where(geodata: {}).count
  end

  def immich_integration_configured?
    settings['immich_url'].present? && settings['immich_api_key'].present?
  end

  def photoprism_integration_configured?
    settings['photoprism_url'].present? && settings['photoprism_api_key'].present?
  end

  def years_tracked
    Rails.cache.fetch("dawarich/user_#{id}_years_tracked", expires_in: 1.day) do
      # Use select_all for better performance with large datasets
      sql = <<-SQL
        SELECT DISTINCT
          EXTRACT(YEAR FROM TO_TIMESTAMP(timestamp)) AS year,
          TO_CHAR(TO_TIMESTAMP(timestamp), 'Mon') AS month
        FROM points
        WHERE user_id = #{id}
        ORDER BY year DESC, month ASC
      SQL

      result = ActiveRecord::Base.connection.select_all(sql)

      result
        .map { |r| [r['year'].to_i, r['month']] }
        .group_by { |year, _| year }
        .transform_values { |year_data| year_data.map { |_, month| month } }
        .map { |year, months| { year: year, months: months } }
    end
  end

  def can_subscribe?
    (trial? || !active_until&.future?) && !DawarichSettings.self_hosted?
  end

  def generate_subscription_token
    payload = {
      user_id: id,
      email: email,
      exp: 30.minutes.from_now.to_i
    }

    secret_key = ENV['JWT_SECRET_KEY']

    JWT.encode(payload, secret_key, 'HS256')
  end

  def export_data
    Users::ExportDataJob.perform_later(id)
  end

  def trial_state?
    (points_count || 0).zero? && trial?
  end

  def timezone
    Time.zone.name
  end

  def countries_visited_uncached
    points
      .without_raw_data
      .where.not(country_name: [nil, ''])
      .distinct
      .pluck(:country_name)
      .compact
  end

  def cities_visited_uncached
    points.where.not(city: [nil, '']).distinct.pluck(:city).compact
  end

  private

  def create_api_key
    self.api_key = SecureRandom.hex(16)

    save
  end

  def activate
    update(status: :active, active_until: 1000.years.from_now)
  end

  def sanitize_input
    settings['immich_url']&.gsub!(%r{/+\z}, '')
    settings['photoprism_url']&.gsub!(%r{/+\z}, '')
    settings.try(:[], 'maps')&.try(:[], 'url')&.strip!
  end

  def check_family_ownership
    return if can_delete_account?

    errors.add(:base, 'Cannot delete account while being a family owner with other members')
    raise ActiveRecord::DeleteRestrictionError, 'Cannot delete user with family members'
  end

  def start_trial
    update(status: :trial, active_until: 7.days.from_now)
    schedule_welcome_emails

    Users::TrialWebhookJob.perform_later(id)
  end

  def schedule_welcome_emails
    Users::MailerSendingJob.perform_later(id, 'welcome')
    Users::MailerSendingJob.set(wait: 2.days).perform_later(id, 'explore_features')
    Users::MailerSendingJob.set(wait: 5.days).perform_later(id, 'trial_expires_soon')
    Users::MailerSendingJob.set(wait: 7.days).perform_later(id, 'trial_expired')
    schedule_post_trial_emails
  end

  def schedule_post_trial_emails
    Users::MailerSendingJob.set(wait: 9.days).perform_later(id, 'post_trial_reminder_early')
    Users::MailerSendingJob.set(wait: 14.days).perform_later(id, 'post_trial_reminder_late')
  end

  public

  # Family-related methods
  def in_family?
    family_membership.present?
  end

  def family_owner?
    family_membership&.owner? == true
  end

  def can_delete_account?
    return true unless family_owner?
    return true unless family

    family.members.count <= 1
  end

  def family_sharing_enabled?
    # User must be in a family and have explicitly enabled location sharing
    return false unless in_family?

    sharing_settings = settings.dig('family', 'location_sharing')
    return false if sharing_settings.blank?

    # If it's a boolean (legacy support), return it
    return sharing_settings if [true, false].include?(sharing_settings)

    # If it's time-limited sharing, check if it's still active
    if sharing_settings.is_a?(Hash)
      return false unless sharing_settings['enabled'] == true

      # Check if sharing has an expiration
      expires_at = sharing_settings['expires_at']
      return expires_at.blank? || Time.parse(expires_at) > Time.current
    end

    false
  end

  def update_family_location_sharing!(enabled, duration: nil)
    return false unless in_family?

    current_settings = settings || {}
    current_settings['family'] ||= {}

    if enabled
      sharing_config = { 'enabled' => true }

      # Add expiration if duration is specified
      if duration.present?
        expiration_time = case duration
        when '1h'
          1.hour.from_now
        when '6h'
          6.hours.from_now
        when '12h'
          12.hours.from_now
        when '24h'
          24.hours.from_now
        when 'permanent'
          nil # No expiration
        else
          # Custom duration in hours
          duration.to_i.hours.from_now if duration.to_i > 0
        end

        sharing_config['expires_at'] = expiration_time.iso8601 if expiration_time
        sharing_config['duration'] = duration
      end

      current_settings['family']['location_sharing'] = sharing_config
    else
      current_settings['family']['location_sharing'] = { 'enabled' => false }
    end

    update!(settings: current_settings)
  end

  def family_sharing_expires_at
    sharing_settings = settings.dig('family', 'location_sharing')
    return nil unless sharing_settings.is_a?(Hash)

    expires_at = sharing_settings['expires_at']
    Time.parse(expires_at) if expires_at.present?
  rescue ArgumentError
    nil
  end

  def family_sharing_duration
    settings.dig('family', 'location_sharing', 'duration') || 'permanent'
  end

  def latest_location_for_family
    return nil unless family_sharing_enabled?

    # Use select to only fetch needed columns and limit to 1 for efficiency
    latest_point = points.select(:latitude, :longitude, :timestamp)
                         .order(timestamp: :desc)
                         .limit(1)
                         .first

    return nil unless latest_point

    {
      user_id: id,
      email: email,
      latitude: latest_point.latitude,
      longitude: latest_point.longitude,
      timestamp: latest_point.timestamp,
      updated_at: Time.at(latest_point.timestamp)
    }
  end
end
