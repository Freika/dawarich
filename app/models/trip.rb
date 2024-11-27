# frozen_string_literal: true

class Trip < ApplicationRecord
  belongs_to :user

  validates :name, :started_at, :ended_at, presence: true

  def points
    user.points.where(timestamp: started_at.to_i..ended_at.to_i).order(:timestamp)
  end

  def countries
    points.pluck(:country).uniq.compact
  end
end
