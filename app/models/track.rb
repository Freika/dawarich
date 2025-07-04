# frozen_string_literal: true

class Track < ApplicationRecord
  include Calculateable

  belongs_to :user
  has_many :points, dependent: :nullify

  validates :start_at, :end_at, :original_path, presence: true
  validates :distance, :avg_speed, :duration, numericality: { greater_than: 0 }

  after_update :recalculate_path_and_distance!, if: -> { points.exists? && (saved_change_to_start_at? || saved_change_to_end_at?) }
end
