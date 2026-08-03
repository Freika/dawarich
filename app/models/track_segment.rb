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

  scope :auto_classified, -> { where(corrected_at: nil) }
  scope :manually_corrected, -> { where.not(corrected_at: nil) }

  def manually_corrected?
    corrected_at.present?
  end

  private

  def end_index_greater_than_or_equal_to_start_index
    return if end_index.nil? || start_index.nil?

    return unless end_index < start_index

    errors.add(:end_index,
               I18n.t('models.track_segment.must_be_greater_than_or_equal_to_start_index'))
  end
end
