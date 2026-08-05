# frozen_string_literal: true

module TransportationModes
  # Fleet-wide staged reclassification after the transportation modes rewrite.
  #
  # NOT enqueued automatically: start it manually from a console once the
  # release is deployed and the TimeAnchorBackfillJob has finished:
  #
  #   TransportationModes::FleetReclassifyJob.perform_later
  #
  # Walks all track ids with a cursor, fanning out ReclassifyTrackJob in
  # staggered slices on low_priority, then re-enqueues itself. Safe to re-run.
  class FleetReclassifyJob < ApplicationJob
    queue_as :low_priority

    BATCH = 1_000
    SLICE = 100
    SLICE_STAGGER = 30.seconds
    NEXT_BATCH_DELAY = 10.minutes

    def perform(from_track_id = 0)
      ids = Track.where(id: (from_track_id + 1)..).order(:id).limit(BATCH).pluck(:id)
      return if ids.empty?

      ids.each_slice(SLICE).with_index do |slice, slice_index|
        jobs = slice.map do |track_id|
          job = ReclassifyTrackJob.new(track_id)
          job.scheduled_at = (slice_index * SLICE_STAGGER).from_now
          job
        end
        ActiveJob.perform_all_later(jobs)
      end

      # Self-re-enqueue relies on queue_as — never set(queue:) here (dropped
      # silently for self-rescheduling jobs).
      self.class.set(wait: NEXT_BATCH_DELAY).perform_later(ids.last)
    end
  end
end
