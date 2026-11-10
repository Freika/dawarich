# frozen_string_literal: true

# Where a Trip came from, and whether the user has touched it since (ADR 0030).
module TripDetectionOrigin
  extend ActiveSupport::Concern

  included do
    enum :origin, { manual: 0, detected: 1 }, prefix: :origin

    # Detected Trips the user left alone: not edited, annotated or shared.
    scope :replaceable_by_detection, lambda {
      notes = Note.where(attachable_type: 'Trip').where('notes.attachable_id = trips.id')
      links = SharedLink.where(resource_type: :trip).where('shared_links.resource_id = trips.id')

      origin_detected.where(user_edited_at: nil).where.not(notes.arel.exists).where.not(links.arel.exists)
    }
  end

  def destroy_by_user!
    transaction do
      user.trip_detection_dismissals.create!(started_at:, ended_at:) if origin_detected?
      destroy!
    end
  end
end
