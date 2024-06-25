# frozen_string_literal: true

class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :imports, dependent: :destroy
  has_many :points, through: :imports
  has_many :stats, dependent: :destroy
  has_many :tracked_points, class_name: 'Point', dependent: :destroy
  has_many :exports, dependent: :destroy

  after_create :create_api_key

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

  def total_km
    stats.sum(:distance)
  end

  def total_countries
    countries_visited.size
  end

  def total_cities
    cities_visited.size
  end

  def total_reverse_geocoded
    points.select(:id).where.not(country: nil, city: nil).count
  end

  private

  def create_api_key
    self.api_key = SecureRandom.hex(16)

    save
  end
end
