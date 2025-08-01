# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable

  has_many :tracked_points, class_name: 'Point', dependent: :destroy
  has_many :imports,        dependent: :destroy
  has_many :stats,          dependent: :destroy
  has_many :exports,        dependent: :destroy
  has_many :notifications,  dependent: :destroy
  has_many :areas,          dependent: :destroy
  has_many :visits,         dependent: :destroy
  has_many :points, through: :imports
  has_many :places, through: :visits
  has_many :trips,  dependent: :destroy
  has_many :tracks, dependent: :destroy

  after_create :create_api_key
  after_commit :activate, on: :create, if: -> { DawarichSettings.self_hosted? }
  before_save :sanitize_input

  validates :email, presence: true

  validates :reset_password_token, uniqueness: true, allow_nil: true

  attribute :admin, :boolean, default: false

  enum :status, { inactive: 0, active: 1 }

  def safe_settings
    Users::SafeSettings.new(settings)
  end

  def countries_visited
    tracked_points
      .where.not(country_name: [nil, ''])
      .distinct
      .pluck(:country_name)
      .compact
  end

  def cities_visited
    tracked_points.where.not(city: [nil, '']).distinct.pluck(:city).compact
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
    tracked_points.where.not(reverse_geocoded_at: nil).count
  end

  def total_reverse_geocoded_points_without_data
    tracked_points.where(geodata: {}).count
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
    (active_until.nil? || active_until&.past?) && !DawarichSettings.self_hosted?
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

  private

  def create_api_key
    self.api_key = SecureRandom.hex(16)

    save
  end

  def activate
    # TODO: Remove the `status` column in the future.
    update(status: :active, active_until: 1000.years.from_now)
  end

  def sanitize_input
    settings['immich_url']&.gsub!(%r{/+\z}, '')
    settings['photoprism_url']&.gsub!(%r{/+\z}, '')
    settings.try(:[], 'maps')&.try(:[], 'url')&.strip!
  end
end
