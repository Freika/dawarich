# frozen_string_literal: true

class User < ApplicationRecord
  include UserFamily
  include Omniauthable
  include PlanScopable
  include SoftDeletable # introduces default_scope and soft-delete methods

  attr_accessor :skip_auto_trial

  devise :two_factor_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable,
         :lockable,
         :omniauthable, omniauth_providers: ::OMNIAUTH_PROVIDERS
  devise :two_factor_backupable, otp_backup_code_length: 12, otp_number_of_backup_codes: 10

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
  after_commit :activate, on: :create, if: -> { DawarichSettings.self_hosted? && !skip_auto_trial }
  after_commit :start_trial, on: :create, if: -> { !DawarichSettings.self_hosted? && !skip_auto_trial }

  before_save :sanitize_input

  validates :email, presence: true
  validates :reset_password_token, uniqueness: true, allow_nil: true

  attribute :admin, :boolean, default: false
  attribute :points_count, :integer, default: 0

  scope :active_or_trial, -> { where(status: %i[active trial]) }

  enum :status, { inactive: 0, active: 1, trial: 2, pending_payment: 3 }
  # prefix: :sub_source — the `none` value would otherwise generate a
  # `User#none?` predicate that collides with NilClass semantics in
  # conditional chains. Callers use `user.sub_source_none?` etc.
  enum :subscription_source, { none: 0, paddle: 1, apple_iap: 2, google_play: 3 }, default: :none, prefix: :sub_source
  enum :plan, { lite: 0, pro: 1 }, default: :pro

  def oauth_user?
    provider.present?
  end

  def safe_settings
    Users::SafeSettings.new(settings, plan: plan)
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

  # Users whose subscription_source is anything other than :none already
  # have a payment source on file (card / App Store / Play Store) and will
  # auto-convert on day 7 without any action from them. The navbar's trial
  # countdown CTA is misleading for them — they don't need to "Subscribe";
  # they're already subscribed and in the trial period. Use this to suppress
  # the CTA on reverse-trial signups and IAP purchases.
  def auto_converting_trial?
    trial? && active_until&.future? && !sub_source_none?
  end

  # Issues a short-lived JWT used to hand the user off to the external
  # subscription Manager (checkout, account portal, etc).
  #
  # Two defense-in-depth claims:
  #
  # * `purpose: 'checkout'` — narrows the token to its intended audience.
  #   Manager (the consumer) ignores unknown claims today, but if a future
  #   Dawarich endpoint ever decodes via `Subscription::DecodeJwtToken` it
  #   should reject any token whose purpose doesn't match. This prevents a
  #   leaked checkout token from being replayed against an unrelated
  #   endpoint that happens to share the JWT secret.
  #
  # * `jti` (random per token) — gives Manager (or future Dawarich code) a
  #   stable identifier for one-shot revocation, mirroring the JTI rotation
  #   we use on the OTP challenge token.
  #
  # NOTE: do NOT reject tokens missing `purpose`/`jti` in
  # `Subscription::DecodeJwtToken`. The manager → dawarich callback path
  # uses a different claim shape (event_id, event_timestamp_ms, etc) and
  # does not include these claims.
  def generate_subscription_token(plan: nil, interval: nil, variant: nil)
    payload = {
      user_id: id,
      email: email,
      purpose: 'checkout',
      jti: SecureRandom.uuid,
      exp: 30.minutes.from_now.to_i
    }
    payload[:plan] = plan if plan.present?
    payload[:interval] = interval if interval.present?
    payload[:variant] = variant if variant.present?

    # Fail loud at boot/runtime if JWT_SECRET_KEY is unset rather than
    # silently signing with nil (which would still produce a "valid" token
    # against any other process that also reads a missing env var).
    secret_key = ENV.fetch('JWT_SECRET_KEY')

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
  # Only counts a country if the user spent meaningful time in at least one city
  # (i.e., the country has non-empty cities array in at least one month)
  def countries_visited_uncached
    countries = Set.new

    stats.find_each do |stat|
      toponyms = stat.toponyms
      next unless toponyms.is_a?(Array)

      toponyms.each do |toponym|
        next unless toponym.is_a?(Hash)
        next if toponym['country'].blank?
        next unless toponym['cities'].is_a?(Array) && toponym['cities'].any?

        countries.add(toponym['country'])
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
    update(status: :active, active_until: 1000.years.from_now, plan: :pro)
  end

  def sanitize_input
    settings['immich_url']&.gsub!(%r{/+\z}, '')
    settings['photoprism_url']&.gsub!(%r{/+\z}, '')
    settings.try(:[], 'maps')&.try(:[], 'url')&.strip!
  end

  def start_trial
    update(status: :trial, active_until: 7.days.from_now)

    Users::MailerSendingJob.perform_later(id, 'welcome')
    Users::MailerSendingJob.set(wait: 2.days).perform_later(id, 'explore_features')

    Users::TrialWebhookJob.perform_later(id)
  end
end
