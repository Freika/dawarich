# frozen_string_literal: true

# Unified background job for all track processing operations.
#
# This job replaces the previous complex system of multiple job types with a single,
# configurable job that handles both bulk and incremental track processing.
#
# Modes:
# - bulk: Process all unassigned points for a user (typically for initial setup)
# - incremental: Process recent points for real-time track updates
#
# Features:
# - Configurable processing modes
# - Point-specific processing for incremental updates
# - Automatic error handling and reporting
# - Smart batching via unique_for to prevent job queue overflow
#
# Usage:
#   # Bulk processing
#   TrackProcessingJob.perform_later(user.id, 'bulk', cleanup_tracks: true)
#
#   # Incremental processing
#   TrackProcessingJob.perform_later(user.id, 'incremental', point_id: point.id)
#
class TrackProcessingJob < ApplicationJob
  queue_as :tracks
  sidekiq_options retry: 3
  
  # Enable unique jobs to prevent duplicate processing
  sidekiq_options unique_for: 30.seconds, 
                  unique_args: ->(args) { [args[0], args[1]] } # user_id and mode
  
  def perform(user_id, mode, **options)
    user = User.find(user_id)
    
    service_options = {
      mode: mode.to_sym,
      cleanup_tracks: options[:cleanup_tracks] || false,
      point_id: options[:point_id],
      time_threshold_minutes: options[:time_threshold_minutes],
      distance_threshold_meters: options[:distance_threshold_meters]
    }.compact
    
    # Additional validation for incremental mode
    if mode == 'incremental' && options[:point_id]
      point = Point.find_by(id: options[:point_id])
      if point.nil?
        Rails.logger.warn "Point #{options[:point_id]} not found for track processing"
        return
      end
      
      # Skip processing old points to avoid processing imported data
      if point.created_at < 1.hour.ago
        Rails.logger.debug "Skipping track processing for old point #{point.id}"
        return
      end
    end
    
    tracks_created = TrackService.new(user, **service_options).call
    
    Rails.logger.info "Track processing completed for user #{user_id}: #{tracks_created} tracks created"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "User #{user_id} not found for track processing: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Track processing failed for user #{user_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    ExceptionReporter.call(e, "Track processing failed", {
      user_id: user_id,
      mode: mode,
      options: options
    })
    
    raise
  end
end