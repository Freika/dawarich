# frozen_string_literal: true

# A period during which a user lived at a Place. A nil date is an open end.
class Home < ApplicationRecord
  belongs_to :user
  belongs_to :place

  validates :ended_on, comparison: { greater_than_or_equal_to: :started_on }, allow_nil: true, if: :started_on
  validate :place_belongs_to_user

  after_create :clear_place_period
  after_commit -> { Trips::DetectJob.schedule(user_id) }, on: %i[create update destroy]

  scope :in_effect_on, lambda { |date|
    where('homes.started_on IS NULL OR homes.started_on <= ?', date)
      .where('homes.ended_on IS NULL OR homes.ended_on >= ?', date)
  }

  private

  # A Home shows only its Home periods, so its Place gives up its own period. update_columns keeps the
  # Place's pending commit callbacks intact: a save here would reset what they check.
  def clear_place_period
    place.update_columns(started_on: nil, ended_on: nil) if place.started_on || place.ended_on
  end

  def place_belongs_to_user
    return if place.nil? || place.user_id == user_id

    errors.add(:place, :invalid)
  end
end
