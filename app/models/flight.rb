# frozen_string_literal: true

class Flight < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true
  validates :external_id, uniqueness: { scope: :user_id }

  scope :mappable, lambda {
    where.not(from_lat: nil).where.not(from_lon: nil).where.not(to_lat: nil).where.not(to_lon: nil)
  }
end
