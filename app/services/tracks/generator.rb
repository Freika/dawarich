# frozen_string_literal: true

# The core track generation engine that orchestrates the entire process of creating tracks from GPS points.
#
# This class uses a flexible strategy pattern to handle different track generation scenarios:
# - Bulk processing: Generate all tracks at once from existing points
# - Incremental processing: Generate tracks as new points arrive
#
# How it works:
# 1. Uses a PointLoader strategy to load points from the database
# 2. Applies segmentation logic to split points into track segments based on time/distance gaps
# 3. Determines which segments should be finalized into tracks vs buffered for later
# 4. Creates Track records from finalized segments with calculated statistics
# 5. Manages cleanup of existing tracks based on the chosen strategy
#
# Strategy Components:
# - point_loader: Loads points from database (BulkLoader, IncrementalLoader)
# - incomplete_segment_handler: Handles segments that aren't ready to finalize (IgnoreHandler, BufferHandler)
# - track_cleaner: Manages existing tracks when regenerating (ReplaceCleaner, NoOpCleaner)
#
# The class includes Tracks::Segmentation for splitting logic and Tracks::TrackBuilder for track creation.
# Distance and time thresholds are configurable per user via their settings.
#
# Example usage:
#   generator = Tracks::Generator.new(
#     user,
#     point_loader: Tracks::PointLoaders::BulkLoader.new(user),
#     incomplete_segment_handler: Tracks::IncompleteSegmentHandlers::IgnoreHandler.new(user),
#     track_cleaner: Tracks::TrackCleaners::ReplaceCleaner.new(user)
#   )
#   tracks_created = generator.call
#
module Tracks
  class Generator
    include Tracks::Segmentation
    include Tracks::TrackBuilder

    attr_reader :user, :point_loader, :incomplete_segment_handler, :track_cleaner

    def initialize(user, point_loader:, incomplete_segment_handler:, track_cleaner:)
      @user = user
      @point_loader = point_loader
      @incomplete_segment_handler = incomplete_segment_handler
      @track_cleaner = track_cleaner
    end

    def call
      Rails.logger.info "Starting track generation for user #{user.id}"

      tracks_created = 0

      Point.transaction do
        # Clean up existing tracks if needed
        track_cleaner.cleanup

        # Load points using the configured strategy
        points = point_loader.load_points

        if points.empty?
          Rails.logger.info "No points to process for user #{user.id}"
          return 0
        end

        Rails.logger.info "Processing #{points.size} points for user #{user.id}"

        # Apply segmentation logic
        segments = split_points_into_segments(points)

        Rails.logger.info "Created #{segments.size} segments for user #{user.id}"

        # Process each segment
        segments.each do |segment_points|
          next if segment_points.size < 2

          if incomplete_segment_handler.should_finalize_segment?(segment_points)
            # Create track from finalized segment
            track = create_track_from_points(segment_points)
            if track&.persisted?
              tracks_created += 1
              Rails.logger.debug "Created track #{track.id} with #{segment_points.size} points"
            end
          else
            # Handle incomplete segment according to strategy
            incomplete_segment_handler.handle_incomplete_segment(segment_points)
            Rails.logger.debug "Stored #{segment_points.size} points as incomplete segment"
          end
        end

        # Cleanup any processed buffered data
        incomplete_segment_handler.cleanup_processed_data
      end

      Rails.logger.info "Completed track generation for user #{user.id}: #{tracks_created} tracks created"
      tracks_created
    end

    private

    # Required by Tracks::Segmentation module
    def distance_threshold_meters
      @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i || 500
    end

    def time_threshold_minutes
      @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i || 60
    end
  end
end
