# frozen_string_literal: true

class Area < ApplicationRecord
  include Notable

  reverse_geocoded_by :latitude, :longitude

  belongs_to :user
  has_many :visits, dependent: :destroy

  validates :name, :latitude, :longitude, :radius, presence: true
  validates :radius, numericality: { greater_than: 0 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  alias_attribute :lon, :longitude
  alias_attribute :lat, :latitude

  # A new or reshaped area labels its historical visits right away — the
  # detection pipeline only attributes areas at detection time. One combined
  # registration: same-method after_create_commit/after_update_commit pairs
  # silently override each other.
  after_commit :schedule_visit_relabel, on: %i[create update], if: :relabel_needed?

  def center = [latitude.to_f, longitude.to_f]

  private

  def relabel_needed?
    previously_new_record? ||
      saved_change_to_latitude? || saved_change_to_longitude? || saved_change_to_radius?
  end

  def schedule_visit_relabel
    Areas::RelabelVisitsJob.perform_later(id)
  end
end
