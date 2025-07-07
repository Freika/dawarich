# frozen_string_literal: true

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
        track_cleaner.cleanup_if_needed

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
