# frozen_string_literal: true

class Track < ApplicationRecord
  belongs_to :user

  validates :path, :started_at, :ended_at, presence: true

  before_save :set_path

  def points
    user.tracked_points.where(timestamp: started_at.to_i..ended_at.to_i).order(timestamp: :asc)
  end

  def set_path
    self.path = Tracks::BuildPath.new(points.pluck(:latitude, :longitude)).call
  end
end
