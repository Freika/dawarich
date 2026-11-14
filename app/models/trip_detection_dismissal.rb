# frozen_string_literal: true

# A period the user closed to Trip Detection by deleting a Detected Trip.
class TripDetectionDismissal < ApplicationRecord
  belongs_to :user

  validates :started_at, :ended_at, presence: true
end
