# frozen_string_literal: true

class Track < ApplicationRecord
  include Calculateable

  belongs_to :user
  has_many :points, dependent: :nullify

  validates :start_at, :end_at, :original_path, presence: true
  validates :distance, :avg_speed, :duration, numericality: { greater_than_or_equal_to: 0 }

  after_update :recalculate_path_and_distance!, if: -> { points.exists? && (saved_change_to_start_at? || saved_change_to_end_at?) }
  after_create :broadcast_track_created
  after_update :broadcast_track_updated
  after_destroy :broadcast_track_destroyed

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

  private

  def broadcast_track_created
    broadcast_track_update('created')
  end

  def broadcast_track_updated
    broadcast_track_update('updated')
  end

  def broadcast_track_destroyed
    TracksChannel.broadcast_to(user, {
      action: 'destroyed',
      track_id: id
    })
  end

  def broadcast_track_update(action)
    TracksChannel.broadcast_to(user, {
      action: action,
      track: serialize_track_data
    })
  end

  def serialize_track_data
    {
      id: id,
      start_at: start_at.iso8601,
      end_at: end_at.iso8601,
      distance: distance.to_i,
      avg_speed: avg_speed.to_f,
      duration: duration,
      elevation_gain: elevation_gain,
      elevation_loss: elevation_loss,
      elevation_max: elevation_max,
      elevation_min: elevation_min,
      original_path: original_path.to_s
    }
  end
end
