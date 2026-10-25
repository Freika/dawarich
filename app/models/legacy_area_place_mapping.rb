# frozen_string_literal: true

class LegacyAreaPlaceMapping < ApplicationRecord
  belongs_to :area
  belongs_to :place

  validates :area_id, uniqueness: true
  validate :same_user

  private

  def same_user
    return if area.blank? || place.blank? || area.user_id == place.user_id

    errors.add(:place, 'must belong to the same user as the area')
  end
end
