# frozen_string_literal: true

class User < ApplicationRecord
  include UserFamily
  include Omniauthable
  include SoftDeletable # introduces default_scope and soft-delete methods

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
  has_many :visited_places, through: :visits, source: :place
  has_many :places,         dependent: :destroy
  has_many :tags,           dependent: :destroy
  has_many :trips,  dependent: :destroy
  has_many :tracks, dependent: :destroy
  has_many :raw_data_archives, class_name: 'Points::RawDataArchive', dependent: :destroy
  has_many :digests, class_name: 'Users::Digest', dependent: :destroy

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

  PLANS = %w[self_hosted personal family].freeze

  def family_plan?
    plan_name == 'family'
  end

  def self_hosted_plan?
    plan_name == 'self_hosted'
  end

  def family_feature_available?
    self_hosted_plan? || family_plan?
  end

  def safe_settings
    Users::SafeSettings.new(settings)
  end

  def countries_visited
    Rails.cache.fetch("dawarich/user_#{id}_countries_visited", expires_in: 1.day) do
      countries_visited_uncached
    end
  end

  def cities_visited
    Rails.cache.fetch("dawarich/user_#{id}_cities_visited", expires_in: 1.day) do
      cities_visited_uncached
    end
  end

  def total_distance
    Rails.cache.fetch("dawarich/user_#{id}_total_distance", expires_in: 1.day) do
      total_distance_meters = stats.sum(:distance)
      Stat.convert_distance(total_distance_meters, safe_settings.distance_unit)
    end
  end

  def total_countries
    countries_visited.size
  end

  def total_cities
    cities_visited.size
  end

  def total_reverse_geocoded_points
    StatsQuery.new(self).points_stats[:geocoded]
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

  delegate :timezone, to: :safe_settings

  # Aggregate countries from all stats' toponyms
  # This is more accurate than raw point queries as it uses processed data
  def countries_visited_uncached
    countries = Set.new

    stats.find_each do |stat|
      toponyms = stat.toponyms
      next unless toponyms.is_a?(Array)

      toponyms.each do |toponym|
        next unless toponym.is_a?(Hash)

        countries.add(toponym['country']) if toponym['country'].present?
      end
    end

    countries.to_a.sort
  end

  # Aggregate cities from all stats' toponyms
  # This respects min_minutes_spent_in_city since toponyms are already filtered
  def cities_visited_uncached
    cities = Set.new

    stats.find_each do |stat|
      toponyms = stat.toponyms
      next unless toponyms.is_a?(Array)

      toponyms.each do |toponym|
        next unless toponym.is_a?(Hash)
        next unless toponym['cities'].is_a?(Array)

        toponym['cities'].each do |city|
          next unless city.is_a?(Hash)

          cities.add(city['city']) if city['city'].present?
        end
      end
    end

    cities.to_a.sort
  end

  def home_place_coordinates
    home_tag = tags.find_by('LOWER(name) = ?', 'home')
    return nil unless home_tag
    return nil if home_tag.privacy_zone?

    home_place = home_tag.places.first
    return nil unless home_place

    [home_place.latitude, home_place.longitude]
  end

  def supporter?
    supporter_info[:supporter] == true
  end

  def supporter_platform
    supporter_info[:platform]
  end

  def supporter_info
    return { supporter: false } if safe_settings.supporter_email.blank?

    Supporter::VerifyEmail.new(safe_settings.supporter_email).call
  end

  private

  def create_api_key
    self.api_key = SecureRandom.hex(16)

    save
  end

  def activate
    update(status: :active, active_until: 1000.years.from_now, plan_name: 'self_hosted')
  end

  def sanitize_input
    settings['immich_url']&.gsub!(%r{/+\z}, '')
    settings['photoprism_url']&.gsub!(%r{/+\z}, '')
    settings.try(:[], 'maps')&.try(:[], 'url')&.strip!
  end

  def start_trial
    update(status: :trial, active_until: 7.days.from_now, plan_name: 'personal')
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
