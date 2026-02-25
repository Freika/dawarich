# frozen_string_literal: true

class TrackSegment < ApplicationRecord
  belongs_to :track

  enum :transportation_mode, Track::TRANSPORTATION_MODES

  # Confidence levels for the detection
  enum :confidence, {
    low: 0,
    medium: 1,
    high: 2
  }, prefix: true

  validates :transportation_mode, presence: true
  validates :start_index, :end_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :distance, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :duration, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :avg_speed, :max_speed, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :end_index_greater_than_or_equal_to_start_index

  private

  def end_index_greater_than_or_equal_to_start_index
    return if end_index.nil? || start_index.nil?

    errors.add(:end_index, 'must be greater than or equal to start_index') if end_index < start_index
  end
end
