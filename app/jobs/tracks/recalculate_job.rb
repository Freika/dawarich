# frozen_string_literal: true

class Tracks::RecalculateJob < ApplicationJob
  queue_as :tracks

  def perform(track_id)
    track = Track.find_by(id: track_id)
    unless track
      Rails.logger.warn "[Tracks::RecalculateJob] Track #{track_id} not found"
      return
    end

    track.recalculate_path_and_distance!

    track.broadcast_geojson_updated
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to recalculate track #{track_id}")
  end
end
