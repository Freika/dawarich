# frozen_string_literal: true

class GoogleMaps::PhoneTakeoutImporter
  include Imports::Broadcaster
  include Imports::FileLoader

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import   = import
    @user_id  = user_id
    @file_path = file_path
  end

  BATCH_SIZE = 1000

  def call
    points_data = parse_json.compact.map do |point_data|
      point_data.merge(
        import_id: import.id,
        topic: 'Google Maps Phone Timeline Export',
        tracker_id: 'google-maps-phone-timeline-export',
        user_id: user_id,
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    points_data.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
      bulk_insert_points(batch)
      broadcast_import_progress(import, (batch_index + 1) * BATCH_SIZE)
    end
  end

  private

  def parse_json
    # location-history.json could contain an array of data points
    # or an object with semanticSegments, rawSignals and rawArray
    semantic_segments = []
    raw_signals       = []
    raw_array         = []

    json = load_json_data

    if json.is_a?(Array)
      raw_array = parse_raw_array(json)
    else
      semantic_segments = parse_semantic_segments(json['semanticSegments']) if json['semanticSegments']
      raw_signals = parse_raw_signals(json['rawSignals']) if json['rawSignals']
    end

    semantic_segments + raw_signals + raw_array
  end

  def parse_coordinates(coordinates)
    if coordinates.include?('°')
      coordinates.split(', ').map { _1.chomp('°') }
    else
      coordinates.delete('geo:').split(',')
    end
  end

  def point_hash(lat, lon, timestamp, raw_data)
    {
      lonlat: "POINT(#{lon.to_f} #{lat.to_f})",
      timestamp:,
      raw_data:,
      accuracy: raw_data['accuracyMeters'],
      altitude: raw_data['altitudeMeters'],
      velocity: raw_data['speedMetersPerSecond']
    }
  end

  def parse_visit_place_location(data_point)
    lat, lon = parse_coordinates(data_point['visit']['topCandidate']['placeLocation'])
    timestamp = DateTime.parse(data_point['startTime']).utc.to_i

    point_hash(lat, lon, timestamp, data_point)
  end

  def parse_activity(data_point)
    start_lat, start_lon = parse_coordinates(data_point['activity']['start'])
    start_timestamp = DateTime.parse(data_point['startTime']).utc.to_i

    end_lat, end_lon = parse_coordinates(data_point['activity']['end'])
    end_timestamp = DateTime.parse(data_point['endTime']).utc.to_i

    [
      point_hash(start_lat, start_lon, start_timestamp, data_point),
      point_hash(end_lat, end_lon, end_timestamp, data_point)
    ]
  end

  def parse_timeline_path(data_point)
    data_point['timelinePath'].map do |point|
      lat, lon = parse_coordinates(point['point'])
      start_time = DateTime.parse(data_point['startTime'])
      offset = point['durationMinutesOffsetFromStartTime']

      timestamp = start_time
      timestamp += offset.to_i.minutes if offset.present?

      point_hash(lat, lon, timestamp, data_point)
    end
  end

  def parse_semantic_visit(segment)
    lat, lon = parse_coordinates(segment['visit']['topCandidate']['placeLocation']['latLng'])
    timestamp = DateTime.parse(segment['startTime']).utc.to_i

    point_hash(lat, lon, timestamp, segment)
  end

  def parse_semantic_activity(segment)
    start_lat, start_lon = parse_coordinates(segment['activity']['start']['latLng'])
    start_timestamp = DateTime.parse(segment['startTime']).utc.to_i
    end_lat, end_lon = parse_coordinates(segment['activity']['end']['latLng'])
    end_timestamp = DateTime.parse(segment['endTime']).utc.to_i

    [
      point_hash(start_lat, start_lon, start_timestamp, segment),
      point_hash(end_lat, end_lon, end_timestamp, segment)
    ]
  end

  def parse_semantic_timeline_path(segment)
    segment['timelinePath'].map do |point|
      lat, lon = parse_coordinates(point['point'])
      timestamp = DateTime.parse(point['time']).utc.to_i

      point_hash(lat, lon, timestamp, segment)
    end
  end

  def parse_raw_array(raw_data)
    raw_data.flat_map do |data_point|
      if data_point.dig('visit', 'topCandidate', 'placeLocation')
        parse_visit_place_location(data_point)
      elsif data_point.dig('activity', 'start') && data_point.dig('activity', 'end')
        parse_activity(data_point)
      elsif data_point['timelinePath']
        parse_timeline_path(data_point)
      end
    end.compact
  end

  def parse_semantic_segments(semantic_segments)
    semantic_segments.flat_map do |segment|
      if segment.key?('timelinePath')
        parse_semantic_timeline_path(segment)
      elsif segment.key?('visit')
        parse_semantic_visit(segment)
      else # activities
        # Some activities don't have start latLng
        next if segment.dig('activity', 'start', 'latLng').nil?

        parse_semantic_activity(segment)
      end
    end
  end

  def parse_raw_signals(raw_signals)
    raw_signals.flat_map do |segment|
      next unless segment.dig('position', 'LatLng')

      lat, lon = parse_coordinates(segment['position']['LatLng'])
      timestamp = DateTime.parse(segment['position']['timestamp']).utc.to_i

      point_hash(lat, lon, timestamp, segment)
    end
  end

  def bulk_insert_points(batch)
    unique_batch = batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

    # rubocop:disable Rails/SkipsModelValidations
    Point.upsert_all(
      unique_batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    create_notification("Failed to process phone takeout batch: #{e.message}")
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'Google Maps Phone Takeout Import Error',
      content: message,
      kind: :error
    )
  end
end
