# frozen_string_literal: true

# Merges two consecutive tracks into a single track.
#
# This service combines an older track with a newer track when they represent
# a continuous journey that was split due to timing (e.g., brief pause in
# point collection). The older track absorbs the newer track's points, and
# the newer track is deleted.
#
# Process:
# 1. Validates both tracks exist and are different
# 2. Moves all points from the newer track to the older track
# 3. Recalculates the older track's path and distance
# 4. Destroys the newer track
#
# All operations occur within a transaction for data integrity.
#
# Used by:
# - Tracks::IncrementalGenerator
#
class Tracks::Merger
  include Tracks::TrackBuilder

  def initialize(older_track, newer_track)
    @older_track = older_track
    @newer_track = newer_track
  end

  def call
    return false if invalid_merge?

    ActiveRecord::Base.transaction do
      # Delete segments from both tracks (indices become invalid after merge)
      @older_track.track_segments.delete_all
      @newer_track.track_segments.delete_all

      # Update newer track's points to belong to older track
      @newer_track.points.update_all(track_id: @older_track.id)

      # Update older track's end time to encompass all points
      @older_track.update!(end_at: @newer_track.end_at)

      # Recalculate path and distance with the combined points
      @older_track.recalculate_path_and_distance!

      # Remove the now-empty newer track
      @newer_track.destroy!
    end

    # Re-detect transportation modes for the merged track (non-critical)
    begin
      detect_and_create_segments(@older_track, @older_track.points.order(:timestamp))
    rescue StandardError => e
      Rails.logger.error "Failed to detect segments after merging tracks #{@older_track.id}: #{e.message}"
    end

    true
  rescue StandardError => e
    Rails.logger.error "Failed to merge tracks #{@older_track&.id} and #{@newer_track&.id}: #{e.message}"
    false
  end

  private

  def invalid_merge?
    @older_track.nil? || @newer_track.nil? || @older_track.id == @newer_track.id
  end
end
