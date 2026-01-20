# frozen_string_literal: true

# Job to recalculate a track's path and distance after a point is moved,
# then broadcast the updated track GeoJSON to the frontend via ActionCable.
class Tracks::RecalculateJob < ApplicationJob
  queue_as :tracks

  def perform(track_id)
    Rails.logger.info "[Tracks::RecalculateJob] Starting recalculation for track #{track_id}"

    track = Track.find_by(id: track_id)
    unless track
      Rails.logger.warn "[Tracks::RecalculateJob] Track #{track_id} not found"
      return
    end

    # Recalculate path and distance from the updated points
    Rails.logger.info "[Tracks::RecalculateJob] Recalculating path and distance for track #{track_id}"
    track.recalculate_path_and_distance!

    # Broadcast the updated track as GeoJSON for the map layer
    Rails.logger.info "[Tracks::RecalculateJob] Broadcasting updated GeoJSON for track #{track_id}"
    track.broadcast_geojson_updated

    Rails.logger.info "[Tracks::RecalculateJob] Completed recalculation for track #{track_id}"
  rescue StandardError => e
    Rails.logger.error "[Tracks::RecalculateJob] Failed to recalculate track #{track_id}: #{e.message}"
    Rails.logger.error "[Tracks::RecalculateJob] Backtrace: #{e.backtrace.first(5).join("\n")}"
    ExceptionReporter.call(e, "Failed to recalculate track #{track_id}")
  end
end
