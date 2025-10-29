# frozen_string_literal: true

class User < ApplicationRecord # rubocop:disable Metrics/ClassLength
  include UserFamily

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :omniauthable, omniauth_providers: ::OMNIAUTH_PROVIDERS

  has_many :points, dependent: :destroy
  has_many :imports,        dependent: :destroy
  has_many :stats,          dependent: :destroy
  has_many :exports,        dependent: :destroy
  has_many :notifications,  dependent: :destroy
  has_many :areas,          dependent: :destroy
  has_many :visits,         dependent: :destroy
  has_many :places, through: :visits
  has_many :trips,  dependent: :destroy
  has_many :tracks, dependent: :destroy

  after_create :create_api_key
  after_commit :activate, on: :create, if: -> { DawarichSettings.self_hosted? }
  after_commit :start_trial, on: :create, if: -> { !DawarichSettings.self_hosted? }

  before_save :sanitize_input

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

  def self.from_omniauth(access_token)
    data = access_token.info
    provider = access_token.provider
    uid = access_token.uid

    # First, try to find user by provider and uid (for linked accounts)
    user = User.find_by(provider: provider, uid: uid)

    if user
      # Update tokens for existing user
      if provider == 'patreon'
        user.update_patreon_tokens(access_token)
      end
      return user
    end

    # If not found, try to find by email
    user = User.find_by(email: data['email'])

    if user
      # Update provider and uid for existing user (first-time linking)
      user.update(provider: provider, uid: uid)
      if provider == 'patreon'
        user.update_patreon_tokens(access_token)
      end
      return user
    end

    # Create new user if not found
    user = User.create(
      email: data['email'],
      password: Devise.friendly_token[0, 20],
      provider: provider,
      uid: uid
    )

    if provider == 'patreon'
      user.update_patreon_tokens(access_token)
    end

    user
  end

  def patreon_connected?
    provider == 'patreon' && uid.present?
  end

  def disconnect_patreon!
    return false unless patreon_connected?

    update(
      provider: nil,
      uid: nil,
      patreon_access_token: nil,
      patreon_refresh_token: nil,
      patreon_token_expires_at: nil
    )
  end

  def update_patreon_tokens(auth)
    credentials = auth.credentials
    update(
      patreon_access_token: credentials.token,
      patreon_refresh_token: credentials.refresh_token,
      patreon_token_expires_at: Time.at(credentials.expires_at)
    )
  end

  # Check if user is a patron of a specific creator
  # @param creator_id [String] The Patreon creator ID to check
  # @return [Boolean] true if user is an active patron
  def patron_of?(creator_id)
    return false unless patreon_connected?

    Patreon::PatronChecker.new(self).patron_of?(creator_id)
  end

  # Get all campaigns the user is supporting
  # @return [Array<Hash>] Array of campaign data
  def patreon_memberships
    return [] unless patreon_connected?

    Patreon::PatronChecker.new(self).memberships
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
end
