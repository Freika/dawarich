# frozen_string_literal: true

class Visit < ApplicationRecord
  include Notable

  belongs_to :area, optional: true
  belongs_to :place, optional: true
  belongs_to :user
  has_many :points, dependent: :nullify
  has_many :place_visits, dependent: :destroy
  has_many :suggested_places, through: :place_visits, source: :place

  validates :started_at, :ended_at, :duration, :name, :status, presence: true

  validates :ended_at, comparison: { greater_than: :started_at }

  enum :status, { suggested: 0, confirmed: 1, declined: 2 }

  def coordinates
    points.pluck(:latitude, :longitude).map { [_1[0].to_f, _1[1].to_f] }
  end

  def default_name
    name || area&.name || place&.name
  end

  # in meters
  def default_radius
    return area&.radius if area.present?

    radius = points.map do |point|
      Geocoder::Calculations.distance_between(
        center, [point.lat, point.lon], units: user.safe_settings.distance_unit.to_sym
      )
    end.max

    radius && radius >= 15 ? radius : 15
  end

  def center
    if area.present?
      [area.lat, area.lon]
    elsif place.present?
      [place.lat, place.lon]
    else
      center_from_points
    end
  end

  def center_from_points
    return [0, 0] if points.empty?

    lat_sum = points.sum(&:lat)
    lon_sum = points.sum(&:lon)
    count = points.size.to_f

    [lat_sum / count, lon_sum / count]
  end

  def async_reverse_geocode
    return unless DawarichSettings.reverse_geocoding_enabled?
    return if place.blank?

    ReverseGeocodingJob.perform_later('place', place_id)
  end
end
