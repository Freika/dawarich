# frozen_string_literal: true

class Tracks::RecalculateJob < ApplicationJob
  queue_as :tracks
  OWNER_KEY = 'command:tracks.recalculate'

  def perform(track_id)
    if JobOwnership.with_owner(OWNER_KEY) { :sidekiq } == :not_owner
      return JobCommands.forward('tracks.recalculate', { 'track_id' => track_id }, event_id: job_id,
                                 aggregate_id: track_id, producer: self.class.name)
    end

    track = Track.find_by(id: track_id)
    unless track
      Rails.logger.warn "[Tracks::RecalculateJob] Track #{track_id} not found"
      return
    end

    # A track needs two points to form a path: calculate_path nils the path
    # below that, the presence validation then rejects the save, and the husk
    # would keep rendering its stale geometry forever. Points are nullified on
    # destroy, so a survivor goes back to being an ordinary untracked point.
    if track.points.count < 2
      track.destroy
      return
    end

    Tracks::Recalculator.call(track)
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to recalculate track #{track_id}")
  end
end
