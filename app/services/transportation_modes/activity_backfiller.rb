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

    NEAREST_POINT_WINDOW_SECONDS = 60

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
      return unless data.is_a?(Hash)

      timeline_objects = data['timelineObjects']
      return unless timeline_objects.is_a?(Array)

      timeline_objects.each do |obj|
        next unless obj.is_a?(Hash) && obj['activitySegment']

        process_activity_segment(obj['activitySegment'])
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse import #{@import.id}: #{e.message}"
    end

    def process_google_phone_takeout
      file_content = download_file
      return unless file_content

      data = JSON.parse(file_content)

      raw_signals =
        case data
        when Hash  then data['rawSignals']
        when Array then data
        end
      return unless raw_signals.is_a?(Array)

      sorted_points = @import.points.order(:timestamp, :id).pluck(:id, :timestamp)
      return if sorted_points.empty?

      nearest_activity_records(raw_signals, sorted_points).each do |point_id, (activity_record, _distance)|
        update_point_activity(point_id, activity_record)
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse import #{@import.id}: #{e.message}"
    end

    def process_activity_segment(segment)
      return unless segment.is_a?(Hash)

      motion_data = Points::MotionDataExtractor.from_google_semantic_history(segment)
      return if motion_data.blank?

      start_time = parse_segment_timestamp(segment.dig('duration', 'startTimestamp'))
      end_time = parse_segment_timestamp(segment.dig('duration', 'endTimestamp'))

      return unless start_time && end_time

      @import.points.where(timestamp: start_time..end_time).find_each do |point|
        point.update_column(:motion_data, (point.motion_data || {}).merge(motion_data))
      end
    end

    # One activityRecord per point: when several samples land inside the
    # window of the same point, the closest one wins regardless of file order.
    def nearest_activity_records(raw_signals, sorted_points)
      raw_signals.each_with_object({}) do |signal, chosen|
        next unless signal.is_a?(Hash)

        activity_record = signal['activityRecord']
        next unless activity_record.is_a?(Hash)

        timestamp = parse_timestamp_value(activity_record['timestamp'])
        next unless timestamp

        point_id, point_timestamp = nearest_point(sorted_points, timestamp)
        next unless point_id

        distance = (point_timestamp - timestamp).abs
        next if chosen.key?(point_id) && chosen[point_id].last <= distance

        chosen[point_id] = [activity_record, distance]
      end
    end

    def update_point_activity(point_id, activity_data)
      return if activity_data.blank?

      Point.where(id: point_id).update_all(
        ["motion_data = COALESCE(motion_data, '{}'::jsonb) || ?::jsonb", { 'activityRecord' => activity_data }.to_json]
      )
    end

    def download_file
      @import.file.download
    rescue StandardError => e
      Rails.logger.error "Failed to download file for import #{@import.id}: #{e.message}"
      nil
    end

    # sorted_points is an ascending array of [id, timestamp] pairs.
    def nearest_point(sorted_points, timestamp)
      idx = sorted_points.bsearch_index { |(_, point_timestamp)| point_timestamp > timestamp } || sorted_points.length

      before_point = idx.positive? ? sorted_points[idx - 1] : nil
      after_point  = idx < sorted_points.length ? sorted_points[idx] : nil

      candidates = [before_point, after_point].compact
      nearest = candidates.min_by { |(_, point_timestamp)| (point_timestamp - timestamp).abs }
      return nil unless nearest && (nearest.last - timestamp).abs <= NEAREST_POINT_WINDOW_SECONDS

      nearest
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
