# frozen_string_literal: true

class DataMigrations::BackfillTransportationModesJob < ApplicationJob
  queue_as :data_migrations

  BATCH_SIZE = 1_000
  SLICE_SIZE = 100
  SLICE_STAGGER = 30.seconds
  NEXT_BATCH_DELAY = 10.minutes

  def perform(from_track_id = 0)
    ids = Track.joins(:user)
               .left_joins(:track_segments)
               .where(users: { deleted_at: nil })
               .where('tracks.id > ?', from_track_id)
               .where('track_segments.id IS NULL OR tracks.dominant_mode = ?', Track.dominant_modes.fetch('unknown'))
               .distinct.order('tracks.id').limit(BATCH_SIZE).pluck('tracks.id')
    return if ids.empty?

    ids.each_slice(SLICE_SIZE).with_index do |slice, index|
      jobs = slice.map do |id|
        job = TransportationModes::ReclassifyTrackJob.new(id)
        job.scheduled_at = (index * SLICE_STAGGER).from_now
        job
      end
      ActiveJob.perform_all_later(jobs)
    end

    self.class.set(wait: NEXT_BATCH_DELAY).perform_later(ids.last) if ids.size == BATCH_SIZE
  end
end
