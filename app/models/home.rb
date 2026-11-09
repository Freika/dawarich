# frozen_string_literal: true

# A period during which a user lived at a Place. A nil date is an open end.
class Home < ApplicationRecord
  belongs_to :user
  belongs_to :place

  validates :ended_on, comparison: { greater_than_or_equal_to: :started_on }, allow_nil: true, if: :started_on
  validate :place_belongs_to_user

  scope :in_effect_on, lambda { |date|
    where('homes.started_on IS NULL OR homes.started_on <= ?', date)
      .where('homes.ended_on IS NULL OR homes.ended_on >= ?', date)
  }

  private

  def place_belongs_to_user
    return if place.nil? || place.user_id == user_id

    errors.add(:place, :invalid)
  end
end
