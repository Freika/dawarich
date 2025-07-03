# frozen_string_literal: true

class Track < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :nullify

  validates :start_at, :end_at, :original_path, presence: true
  validates :distance, :avg_speed, :duration, numericality: { greater_than: 0 }
  validates :elevation_gain, :elevation_loss, :elevation_max, :elevation_min,
            numericality: { greater_than_or_equal_to: 0 }

  def calculate_path
    Tracks::BuildPath.new(points.pluck(:lonlat)).call
  end
end
