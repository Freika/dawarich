# frozen_string_literal: true

module TransportationModes
  # Job to extract activity data from import files and update point raw_data.
  # This allows re-processing imports to extract activity information that
  # wasn't captured during the original import.
  #
  # Supports: Google Semantic History, Google Phone Takeout, Overland, OwnTracks
  #
  # Usage:
  #   TransportationModes::ImportBackfillJob.perform_later(import_id)
  #
  class ImportBackfillJob < ApplicationJob
    queue_as :low_priority

    # Sources that may contain activity data
    SUPPORTED_SOURCES = %w[
      google_semantic_history
      google_phone_takeout
      google_records
      owntracks
      geojson
    ].freeze

    def perform(import_id)
      import = Import.find_by(id: import_id)
      return unless import
      return unless SUPPORTED_SOURCES.include?(import.source)
      return unless import.file.attached?

      Rails.logger.info "Starting activity backfill for import #{import_id} (#{import.source})"

      process_import(import)

      # Reprocess affected tracks
      reprocess_tracks_for_import(import)

      Rails.logger.info "Completed activity backfill for import #{import_id}"
    end

    private

    def process_import(import)
      case import.source
      when 'google_semantic_history'
        process_google_semantic_history(import)
      when 'google_phone_takeout'
        process_google_phone_takeout(import)
      when 'owntracks', 'geojson'
        # These formats store activity in raw_data already
        # Just need to reprocess tracks
        nil
      end
    end

    def process_google_semantic_history(import)
      file_content = download_file(import)
      return unless file_content

      data = JSON.parse(file_content)
      timeline_objects = data['timelineObjects'] || []

      timeline_objects.each do |obj|
        next unless obj['activitySegment']

        segment = obj['activitySegment']
        process_activity_segment(import, segment)
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse import #{import.id}: #{e.message}"
    end

    def process_google_phone_takeout(import)
      file_content = download_file(import)
      return unless file_content

      data = JSON.parse(file_content)
      locations = data['locations'] || []

      locations.each do |location|
        next unless location['activityRecord']

        # Find matching point and update raw_data
        timestamp = parse_timestamp(location)
        next unless timestamp

        point = import.points.find_by(timestamp: timestamp)
        next unless point

        # Merge activity data into raw_data
        update_point_activity(point, location['activityRecord'])
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse import #{import.id}: #{e.message}"
    end

    def process_activity_segment(import, segment)
      # Extract activity info
      activities = segment['activities'] || []
      travel_mode = segment.dig('waypointPath', 'travelMode')

      # Find points in this time range
      start_time = parse_segment_timestamp(segment['duration']['startTimestamp'])
      end_time = parse_segment_timestamp(segment['duration']['endTimestamp'])

      return unless start_time && end_time

      # Update matching points
      import.points.where(timestamp: start_time..end_time).find_each do |point|
        activity_data = {
          'activities' => activities,
          'travelMode' => travel_mode,
          'confidence' => segment['confidence']
        }.compact

        update_point_activity(point, activity_data)
      end
    end

    def update_point_activity(point, activity_data)
      return if activity_data.blank?

      current_raw = point.raw_data || {}
      merged_raw = current_raw.merge('activityRecord' => activity_data)

      point.update_column(:raw_data, merged_raw)
    end

    def download_file(import)
      import.file.download
    rescue StandardError => e
      Rails.logger.error "Failed to download file for import #{import.id}: #{e.message}"
      nil
    end

    def parse_timestamp(location)
      ts = location['timestamp'] || location['timestampMs']
      return nil unless ts

      if ts.is_a?(String) && ts.include?('T')
        DateTime.parse(ts).to_i
      elsif ts.to_s.length > 10
        ts.to_i / 1000 # milliseconds
      else
        ts.to_i
      end
    rescue ArgumentError
      nil
    end

    def parse_segment_timestamp(ts)
      return nil unless ts

      if ts.is_a?(String) && ts.include?('T')
        DateTime.parse(ts).to_i
      elsif ts.to_s.length > 10
        ts.to_i / 1000
      else
        ts.to_i
      end
    rescue ArgumentError
      nil
    end

    def reprocess_tracks_for_import(import)
      # Find all tracks that have points from this import
      track_ids = import.points
                        .where.not(track_id: nil)
                        .distinct
                        .pluck(:track_id)

      return if track_ids.empty?

      Rails.logger.info "Reprocessing #{track_ids.size} tracks for import #{import.id}"

      Track.where(id: track_ids).find_each do |track|
        reprocess_track(track)
      end
    end

    def reprocess_track(track)
      points = track.points.order(:timestamp).to_a
      return if points.size < 2

      # Clear existing segments
      track.track_segments.destroy_all

      # Re-detect
      detector = TransportationModes::Detector.new(track, points)
      segment_data = detector.call

      create_segments(track, segment_data)
    rescue StandardError => e
      Rails.logger.error "Failed to reprocess track #{track.id}: #{e.message}"
    end

    def create_segments(track, segment_data)
      return if segment_data.empty?

      segments = segment_data.map do |data|
        track.track_segments.create(
          transportation_mode: data[:mode],
          start_index: data[:start_index],
          end_index: data[:end_index],
          distance: data[:distance],
          duration: data[:duration],
          avg_speed: data[:avg_speed],
          max_speed: data[:max_speed],
          avg_acceleration: data[:avg_acceleration],
          confidence: data[:confidence],
          source: data[:source]
        )
      end.compact

      dominant_segment = segments.max_by { |s| s.duration || 0 }
      track.update_column(:dominant_mode, dominant_segment&.transportation_mode || :unknown)
    end
  end
end
