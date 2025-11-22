# frozen_string_literal: true

class Tag < ApplicationRecord
  belongs_to :user
  has_many :taggings, dependent: :destroy
  has_many :places, through: :taggings, source: :taggable, source_type: 'Place'

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :icon, length: { maximum: 10, allow_blank: true }
  validate :icon_is_not_ascii_letter
  validates :color, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, allow_blank: true }
  validates :privacy_radius_meters, numericality: {
    greater_than: 0,
    less_than_or_equal_to: 5000,
    allow_nil: true
  }

  scope :for_user, ->(user) { where(user: user) }
  scope :ordered, -> { order(:name) }
  scope :privacy_zones, -> { where.not(privacy_radius_meters: nil) }

  def privacy_zone?
    privacy_radius_meters.present?
  end

  private

  def icon_is_not_ascii_letter
    return if icon.blank?
    return unless icon.match?(/\A[a-zA-Z]+\z/)

    errors.add(:icon, 'must be an emoji or symbol, not a letter')
  end
end
