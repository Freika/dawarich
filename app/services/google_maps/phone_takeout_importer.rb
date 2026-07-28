# frozen_string_literal: true

class GoogleMaps::PhoneTakeoutImporter
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include Imports::ActivityTypeMapping

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import   = import
    @user_id  = user_id
    @file_path = file_path
  end

  BATCH_SIZE = 1000

  def call
    path = resolve_file_path
    validate_json(path)
    initialize_stream
    ActiveRecord::Base.transaction do
      stream_entries(path)
      process_user_location_profile
      flush_batch
    end
  ensure
    cleanup_temp_file
  end

  private

  def validate_json(path)
    parser = Oj::Parser.new(:validate)
    File.open(path, 'rb') { |io| parser.load(io) }
  rescue EncodingError, JSON::ParserError
    @legacy_parser_required = true
    File.open(path, 'rb') { |io| Oj.saj_parse(nil, io) }
  end

  def initialize_stream
    @points_batch = []
    @processed_points = 0
    @first_semantic_start_time = nil
    @seen_first_semantic_segment = false
    @user_location_profile = nil
  end

  def stream_entries(path)
    handler = GoogleMaps::PhoneTakeoutStreamHandler.new(
      on_entry: ->(section, value) { process_stream_entry(section, value) },
      on_profile: ->(profile) { @user_location_profile = profile }
    )

    File.open(path, 'rb') do |io|
      if @legacy_parser_required
        Oj.saj_parse(handler, io)
      else
        Oj::Parser.new(:saj, handler:).load(io)
      end
    end
  end

  def process_stream_entry(section, value)
    points = case section
             when :semantic_segment
               capture_first_semantic_start_time(value)
               parse_semantic_segments([value])
             when :raw_signal
               parse_raw_signals([value])
             when :raw_array
               parse_raw_array([value])
             else
               []
             end

    enqueue_points(points)
  end

  def capture_first_semantic_start_time(segment)
    return if @seen_first_semantic_segment

    @first_semantic_start_time = segment['startTime']
    @seen_first_semantic_segment = true
  end

  def enqueue_points(points)
    Array(points).flatten.compact.each do |point|
      @points_batch << point.merge(point_metadata)
      flush_batch if @points_batch.size >= BATCH_SIZE
    end
  end

  def point_metadata
    {
      import_id: import.id,
      topic: 'Google Maps Phone Timeline Export',
      tracker_id: "google-phone-#{import.id}",
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def process_user_location_profile
    return unless @user_location_profile

    enqueue_points(parse_user_location_profile(@user_location_profile, @first_semantic_start_time))
  end

  def flush_batch
    return if @points_batch.empty?

    batch = @points_batch
    @points_batch = []
    bulk_insert_points(batch)
    @processed_points += batch.size
    broadcast_import_progress(import, @processed_points)
  end

  def atomic_bulk_insert?
    true
  end

  def parse_coordinates(coord_string)
    return nil if coord_string.blank?

    cleaned = coord_string.to_s
                          .gsub('geo:', '')
                          .gsub("\u00B0", '')
                          .strip

    parts = cleaned.split(/,\s*/)
    return nil if parts.size < 2

    lat = parts[0].to_f
    lon = parts[1].to_f
    altitude = parts[2]&.to_f

    altitude ? [lat, lon, altitude] : [lat, lon]
  end

  def point_hash(lat, lon, timestamp, raw_data, altitude: nil, activity_type: nil)
    altitude_value = altitude || raw_data['altitudeMeters']
    motion_data = Points::MotionDataExtractor.from_google_phone_takeout(raw_data)
    motion_data['activity_type'] = activity_type if activity_type

    attrs = {
      lonlat: "POINT(#{lon.to_f} #{lat.to_f})",
      timestamp:,
      motion_data: motion_data,
      accuracy: raw_data['accuracyMeters'],
      altitude: altitude_value,
      velocity: raw_data['speedMetersPerSecond']
    }
    attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
    attrs
  end

  def parse_visit_place_location(data_point)
    coords = parse_coordinates(data_point.dig('visit', 'topCandidate', 'placeLocation'))
    return if coords.nil?

    lat, lon, alt = coords
    timestamp = DateTime.parse(data_point['startTime']).utc.to_i

    point_hash(lat, lon, timestamp, data_point, altitude: alt)
  end

  def parse_activity(data_point)
    start_coords = parse_coordinates(data_point.dig('activity', 'start'))
    end_coords = parse_coordinates(data_point.dig('activity', 'end'))
    return if start_coords.nil? || end_coords.nil?

    start_lat, start_lon, start_alt = start_coords
    start_timestamp = DateTime.parse(data_point['startTime']).utc.to_i

    end_lat, end_lon, end_alt = end_coords
    end_timestamp = DateTime.parse(data_point['endTime']).utc.to_i

    [
      point_hash(start_lat, start_lon, start_timestamp, data_point, altitude: start_alt),
      point_hash(end_lat, end_lon, end_timestamp, data_point, altitude: end_alt)
    ]
  end

  def parse_timeline_path(data_point)
    return [] if data_point['startTime'].nil?

    data_point['timelinePath'].filter_map do |point|
      coords = parse_coordinates(point['point'])
      next if coords.nil?

      lat, lon, alt = coords
      start_time = DateTime.parse(data_point['startTime'])
      offset = point['durationMinutesOffsetFromStartTime']

      timestamp = start_time
      timestamp += offset.to_i.minutes if offset.present? && !offset.to_i.negative?

      point_hash(lat, lon, timestamp, data_point, altitude: alt)
    end
  end

  def parse_semantic_visit(segment)
    coords = parse_coordinates(segment.dig('visit', 'topCandidate', 'placeLocation', 'latLng'))
    return if coords.nil?

    lat, lon, alt = coords
    timestamp = DateTime.parse(segment['startTime']).utc.to_i

    point_hash(lat, lon, timestamp, segment, altitude: alt)
  end

  def parse_semantic_activity(segment)
    start_coords = parse_coordinates(segment.dig('activity', 'start', 'latLng'))
    end_coords = parse_coordinates(segment.dig('activity', 'end', 'latLng'))
    return if start_coords.nil? || end_coords.nil?

    start_lat, start_lon, start_alt = start_coords
    start_timestamp = DateTime.parse(segment['startTime']).utc.to_i
    end_lat, end_lon, end_alt = end_coords
    end_timestamp = DateTime.parse(segment['endTime']).utc.to_i

    activity_type = map_activity_type(segment.dig('activity', 'topCandidate', 'type'))

    [
      point_hash(start_lat, start_lon, start_timestamp, segment, altitude: start_alt, activity_type: activity_type),
      point_hash(end_lat, end_lon, end_timestamp, segment, altitude: end_alt, activity_type: activity_type)
    ]
  end

  def parse_semantic_timeline_path(segment)
    segment['timelinePath'].filter_map do |point|
      coords = parse_coordinates(point['point'])
      next if coords.nil?

      lat, lon, alt = coords
      timestamp = DateTime.parse(point['time']).utc.to_i

      point_hash(lat, lon, timestamp, segment, altitude: alt)
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

      coords = parse_coordinates(segment['position']['LatLng'])
      next if coords.nil?

      lat, lon, alt = coords
      timestamp = DateTime.parse(segment['position']['timestamp']).utc.to_i

      point_hash(lat, lon, timestamp, segment, altitude: alt)
    end
  end

  def parse_user_location_profile(profile, reference_time)
    places = profile['frequentPlaces']
    return [] if places.blank?

    # Use midnight of the first semantic segment's date as a base,
    # offset negatively to avoid collisions with actual data points
    base_timestamp = if reference_time
                       DateTime.parse(reference_time).beginning_of_day.utc.to_i
                     else
                       Time.current.beginning_of_day.to_i
                     end

    places.filter_map.with_index do |place, index|
      coords = parse_coordinates(place['placeLocation'])
      next if coords.nil?

      lat, lon, alt = coords
      timestamp = base_timestamp + index

      raw_data = { 'frequent_place_label' => place['label'], 'placeId' => place['placeId'] }
      point_hash(lat, lon, timestamp, raw_data, altitude: alt)
    end
  end

  def importer_name
    'Google Maps Phone Takeout'
  end
end
