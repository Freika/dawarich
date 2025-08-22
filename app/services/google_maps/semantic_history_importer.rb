# frozen_string_literal: true

class GoogleMaps::SemanticHistoryImporter
  include Imports::Broadcaster

  BATCH_SIZE = 1000
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
    @current_index = 0
  end

  def call
    points_data.each_slice(BATCH_SIZE) do |batch|
      @current_index += batch.size
      process_batch(batch)
      broadcast_import_progress(import, @current_index)
    end
  end

  private

  def process_batch(batch)
    records = batch.map { |point_data| prepare_point_data(point_data) }

    # rubocop:disable Rails/SkipsModelValidations
    Point.upsert_all(
      records,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    create_notification("Failed to process location batch: #{e.message}")
  end

  def prepare_point_data(point_data)
    {
      lonlat: point_data[:lonlat],
      timestamp: point_data[:timestamp],
      raw_data: point_data[:raw_data],
      topic: 'Google Maps Timeline Export',
      tracker_id: 'google-maps-timeline-export',
      import_id: import.id,
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'Google Maps Timeline Import Error',
      content: message,
      kind: :error
    )
  end

  def points_data
    json = load_json_data

    json['timelineObjects'].flat_map do |timeline_object|
      parse_timeline_object(timeline_object)
    end.compact
  end

  def load_json_data
    if file_path && File.exist?(file_path)
      # Use streaming JSON loading for better memory efficiency
      Oj.load_file(file_path, mode: :compat)
    else
      # Fallback to traditional method
      file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
      Oj.load(file_content, mode: :compat)
    end
  end

  def parse_timeline_object(timeline_object)
    if timeline_object['activitySegment'].present?
      parse_activity_segment(timeline_object['activitySegment'])
    elsif timeline_object['placeVisit'].present?
      parse_place_visit(timeline_object['placeVisit'])
    end
  end

  def parse_activity_segment(activity)
    if activity['startLocation'].blank?
      parse_waypoints(activity)
    else
      build_point_from_location(
        longitude: activity['startLocation']['longitudeE7'],
        latitude: activity['startLocation']['latitudeE7'],
        timestamp: activity['duration']['startTimestamp'] || activity['duration']['startTimestampMs'],
        raw_data: activity
      )
    end
  end

  def parse_waypoints(activity)
    return if activity['waypointPath'].blank?

    activity['waypointPath']['waypoints'].map do |waypoint|
      build_point_from_location(
        longitude: waypoint['lngE7'],
        latitude: waypoint['latE7'],
        timestamp: activity['duration']['startTimestamp'] || activity['duration']['startTimestampMs'],
        raw_data: activity
      )
    end
  end

  def parse_place_visit(place_visit)
    if place_visit.dig('location', 'latitudeE7').present? &&
       place_visit.dig('location', 'longitudeE7').present?
      build_point_from_location(
        longitude: place_visit['location']['longitudeE7'],
        latitude: place_visit['location']['latitudeE7'],
        timestamp: place_visit['duration']['startTimestamp'] || place_visit['duration']['startTimestampMs'],
        raw_data: place_visit
      )
    elsif (candidate = place_visit.dig('otherCandidateLocations', 0))
      parse_candidate_location(candidate, place_visit)
    end
  end

  def parse_candidate_location(candidate, place_visit)
    return unless candidate['latitudeE7'].present? && candidate['longitudeE7'].present?

    build_point_from_location(
      longitude: candidate['longitudeE7'],
      latitude: candidate['latitudeE7'],
      timestamp: place_visit['duration']['startTimestamp'] || place_visit['duration']['startTimestampMs'],
      raw_data: place_visit
    )
  end

  def build_point_from_location(longitude:, latitude:, timestamp:, raw_data:)
    {
      lonlat: "POINT(#{longitude.to_f / 10**7} #{latitude.to_f / 10**7})",
      timestamp: Timestamps.parse_timestamp(timestamp),
      raw_data: raw_data
    }
  end
end
