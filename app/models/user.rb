# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, and :omniauthable
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
  has_many :trips, dependent: :destroy

  after_create :create_api_key
  before_save :strip_trailing_slashes

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
      tracked_points
        .pluck(:timestamp)
        .map { |ts| Time.zone.at(ts) }
        .group_by(&:year)
        .transform_values do |dates|
          dates.map { |date| date.strftime('%b') }.uniq.sort
        end
        .map { |year, months| { year: year, months: months } }
        .sort_by { |entry| -entry[:year] } # Sort in descending order
    end
  end

  private

  def create_api_key
    self.api_key = SecureRandom.hex(16)

    save
  end

  def strip_trailing_slashes
    settings['immich_url']&.gsub!(%r{/+\z}, '')
    settings['photoprism_url']&.gsub!(%r{/+\z}, '')
  end
end
