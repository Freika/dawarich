# frozen_string_literal: true

class Visit < ApplicationRecord
  belongs_to :area, optional: true
  belongs_to :place, optional: true
  belongs_to :user
  has_many :points, dependent: :nullify
  has_many :place_visits, dependent: :destroy
  has_many :suggested_places, through: :place_visits, source: :place

  validates :started_at, :ended_at, :duration, :name, :status, presence: true

  enum status: { suggested: 0, confirmed: 1, declined: 2 }

  def coordinates
    points.pluck(:latitude, :longitude).map { [_1[0].to_f, _1[1].to_f] }
  end

  def default_name
    name || area&.name || place&.name
  end

  # in meters
  def default_radius
    return area&.radius if area.present?

    radius = points.map { Geocoder::Calculations.distance_between(center, [_1.latitude, _1.longitude]) }.max

    radius >= 15 ? radius : 15
  end

  def center
    area.present? ? [area.latitude, area.longitude] : [place.latitude, place.longitude]
  end

  def async_reverse_geocode
    return unless REVERSE_GEOCODING_ENABLED
    return if place.blank?

    # If place is successfully reverse geocoded, try to add it to corresponding visits as suggested
    ReverseGeocodingJob.perform_later('place', place_id)
  end
end
