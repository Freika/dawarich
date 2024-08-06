# frozen_string_literal: true

class Visit < ApplicationRecord
  belongs_to :area
  belongs_to :user
  has_many :points, dependent: :nullify

  validates :started_at, :ended_at, :duration, :name, :status, presence: true

  enum status: { suggested: 0, confirmed: 1, declined: 2 }

  delegate :name, to: :area, prefix: true

  def coordinates
    points.pluck(:latitude, :longitude).map { [_1[0].to_f, _1[1].to_f] }
  end
end
