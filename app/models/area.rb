# frozen_string_literal: true

class Area < ApplicationRecord
  include Notable

  attr_accessor :skip_visit_relabel

  reverse_geocoded_by :latitude, :longitude

  belongs_to :user
  has_many :visits, dependent: :nullify

  validates :name, :latitude, :longitude, :radius, presence: true
  validates :radius, numericality: { greater_than: 0 }
  validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  alias_attribute :lon, :longitude
  alias_attribute :lat, :latitude

  # Compatibility-only Area writes forward to the canonical Place workflow.
  # The public legacy adapters suppress this callback because they update the
  # corresponding Place in the same transaction themselves.
  after_commit :schedule_visit_relabel, on: %i[create update], if: :relabel_needed?

  def center = [latitude.to_f, longitude.to_f]

  private

  def relabel_needed?
    return false if skip_visit_relabel

    previously_new_record? ||
      saved_change_to_latitude? || saved_change_to_longitude? || saved_change_to_radius?
  end

  def schedule_visit_relabel
    Areas::RelabelVisitsJob.perform_later(id)
  end
end
