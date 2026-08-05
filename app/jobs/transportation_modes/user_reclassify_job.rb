# frozen_string_literal: true

module TransportationModes
  # User-triggered reclassification (Recalculate button): starts progress
  # tracking and fans out per-track jobs that report back on completion.
  class UserReclassifyJob < ApplicationJob
    queue_as :tracks

    SLICE = 100
    SLICE_STAGGER = 10.seconds

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user

      status = Tracks::TransportationRecalculationStatus.new(user.id)
      track_ids = user.tracks.order(:id).pluck(:id)
      status.start(total_tracks: track_ids.size)

      return status.complete if track_ids.empty?

      track_ids.each_slice(SLICE).with_index do |slice, slice_index|
        jobs = slice.map do |track_id|
          job = ReclassifyTrackJob.new(track_id, report_progress: true)
          job.scheduled_at = (slice_index * SLICE_STAGGER).from_now
          job
        end
        ActiveJob.perform_all_later(jobs)
      end
    end
  end
end
