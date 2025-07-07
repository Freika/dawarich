# frozen_string_literal: true

class Track < ApplicationRecord
  include Calculateable

  belongs_to :user
  has_many :points, dependent: :nullify

  validates :start_at, :end_at, :original_path, presence: true
  validates :distance, :avg_speed, :duration, numericality: { greater_than_or_equal_to: 0 }

  after_update :recalculate_path_and_distance!, if: -> { points.exists? && (saved_change_to_start_at? || saved_change_to_end_at?) }

  # Find the last track for a user on a specific day
  # @param user [User] the user to find tracks for
  # @param day [Date, Time] the day to search for tracks
  # @return [Track, nil] the last track for that day or nil if none found
  def self.last_for_day(user, day)
    day_start = day.beginning_of_day
    day_end = day.end_of_day

    where(user: user)
      .where(end_at: day_start..day_end)
      .order(end_at: :desc)
      .first
  end
end
