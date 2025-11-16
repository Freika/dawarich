# frozen_string_literal: true

class Tag < ApplicationRecord
  belongs_to :user
  has_many :taggings, dependent: :destroy
  has_many :places, through: :taggings, source: :taggable, source_type: 'Place'

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :color, format: { with: /\A#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})\z/, allow_blank: true }

  scope :for_user, ->(user) { where(user: user) }
  scope :ordered, -> { order(:name) }
end
