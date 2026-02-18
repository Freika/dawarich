# frozen_string_literal: true

module TransportationModes
  # Extracts activity data from import files and updates points' motion_data.
  # Supports Google Semantic History and Google Phone Takeout formats.
  class ActivityBackfiller
    SUPPORTED_SOURCES = %w[
      google_semantic_history
      google_phone_takeout
      google_records
      owntracks
      geojson
    ].freeze

    def initialize(import)
      @import = import
    end

    def call
      return false unless supported?
      return false unless @import.file.attached?

      process_import
      true
    end

    def supported?
      SUPPORTED_SOURCES.include?(@import.source)
    end

    private

    def process_import
      case @import.source
      when 'google_semantic_history'
        process_google_semantic_history
      when 'google_phone_takeout'
        process_google_phone_takeout
      when 'owntracks', 'geojson'
        # These formats store activity in raw_data already during import
        nil
      end
    end

    def process_google_semantic_history
      file_content = download_file
      return unless file_content

      data = JSON.parse(file_content)
      timeline_objects = data['timelineObjects'] || []

      timeline_objects.each do |obj|
        next unless obj['activitySegment']

        process_activity_segment(obj['activitySegment'])
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse import #{@import.id}: #{e.message}"
    end

    def process_google_phone_takeout
      file_content = download_file
      return unless file_content

      data = JSON.parse(file_content)
      locations = data['locations'] || []

      locations.each do |location|
        next unless location['activityRecord']

        timestamp = parse_timestamp(location)
        next unless timestamp

        point = @import.points.find_by(timestamp: timestamp)
        next unless point

        update_point_activity(point, location['activityRecord'])
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse import #{@import.id}: #{e.message}"
    end

    def process_activity_segment(segment)
      activities = segment['activities'] || []
      travel_mode = segment.dig('waypointPath', 'travelMode')

      start_time = parse_segment_timestamp(segment['duration']['startTimestamp'])
      end_time = parse_segment_timestamp(segment['duration']['endTimestamp'])

      return unless start_time && end_time

      @import.points.where(timestamp: start_time..end_time).find_each do |point|
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

      current_motion = point.motion_data || {}
      merged_motion = current_motion.merge('activityRecord' => activity_data)

      point.update_column(:motion_data, merged_motion) # rubocop:disable Rails/SkipsModelValidations
    end

    def download_file
      @import.file.download
    rescue StandardError => e
      Rails.logger.error "Failed to download file for import #{@import.id}: #{e.message}"
      nil
    end

    def parse_timestamp(location)
      ts = location['timestamp'] || location['timestampMs']
      parse_timestamp_value(ts)
    end

    def parse_segment_timestamp(timestamp)
      parse_timestamp_value(timestamp)
    end

    def parse_timestamp_value(timestamp)
      return nil unless timestamp

      Timestamps.parse_timestamp(timestamp)
    end
  end
end
