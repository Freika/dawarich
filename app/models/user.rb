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

  has_many_attached :import_files

  after_create :create_api_key
  after_create :import_sample_points
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
    stats.pluck(:toponyms).flatten.map { _1['country'] }.uniq.compact
  end

  def cities_visited
    stats
      .where.not(toponyms: nil)
      .pluck(:toponyms)
      .flatten
      .reject { |toponym| toponym['cities'].blank? }
      .pluck('cities')
      .flatten
      .pluck('city')
      .uniq
      .compact
  end

  def total_distance
    # In km or miles, depending on the application settings (DISTANCE_UNIT)
    stats.sum(:distance)
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

  private

  def create_api_key
    self.api_key = SecureRandom.hex(16)

    save
  end

  def activate
    update(status: :active)
  end

  def sanitize_input
    settings['immich_url']&.gsub!(%r{/+\z}, '')
    settings['photoprism_url']&.gsub!(%r{/+\z}, '')
    settings.try(:[], 'maps')&.try(:[], 'url')&.strip!
  end

  def import_sample_points
    return unless Rails.env.development? ||
                  Rails.env.production? ||
                  (Rails.env.test? && ENV['IMPORT_SAMPLE_POINTS'])

    import = imports.create(
      name: 'DELETE_ME_this_is_a_demo_import_DELETE_ME',
      source: 'gpx'
    )

    import.file.attach(
      Rack::Test::UploadedFile.new(
        Rails.root.join('lib/assets/sample_points.gpx'), 'application/xml'
      )
    )
  end
end
