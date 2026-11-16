# frozen_string_literal: true

class Tag < ApplicationRecord
  include Demoable

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

  WORK_ICON = '💼'

  # The user's Work tag, under its English or its localized name.
  def self.work_tag(user)
    names = [I18n.t('places.shortcuts.work_place_name'), 'Work'].uniq
    user.tags.order(:id).find_by('lower(name) IN (?)', names.map(&:downcase))
  end

  def self.work_tag!(user)
    work_tag(user) ||
      user.tags.create!(name: I18n.t('places.shortcuts.work_place_name'), icon: WORK_ICON, color: '#33FF57')
  end

  def privacy_zone?
    privacy_radius_meters.present?
  end

  private

  def icon_is_not_ascii_letter
    return if icon.blank?
    return unless icon.match?(/\A[a-zA-Z]+\z/)

    errors.add(:icon, I18n.t('models.tag.must_be_an_emoji_or_symbol_not_a_letter'))
  end
end
