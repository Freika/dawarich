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

    frequent_places = []
    frequent_places = parse_user_location_profile(json) if json.is_a?(Hash) && json['userLocationProfile']

    semantic_segments + raw_signals + raw_array + frequent_places
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

  def point_hash(lat, lon, timestamp, raw_data, altitude: nil)
    altitude_value = altitude || raw_data['altitudeMeters']

    attrs = {
      lonlat: "POINT(#{lon.to_f} #{lat.to_f})",
      timestamp:,
      motion_data: Points::MotionDataExtractor.from_google_phone_takeout(raw_data),
      raw_data:,
      accuracy: raw_data['accuracyMeters'],
      altitude: altitude_value,
      velocity: raw_data['speedMetersPerSecond']
    }
    attrs[:altitude_decimal] = altitude_value if Point.column_names.include?('altitude_decimal')
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

    source_type = segment.dig('activity', 'topCandidate', 'type')
    enriched = segment
    if source_type
      mapped = map_activity_type(source_type)
      enriched = segment.merge('activity_type' => mapped) if mapped
    end

    [
      point_hash(start_lat, start_lon, start_timestamp, enriched, altitude: start_alt),
      point_hash(end_lat, end_lon, end_timestamp, enriched, altitude: end_alt)
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

  def parse_user_location_profile(json)
    places = json.dig('userLocationProfile', 'frequentPlaces')
    return [] if places.blank?

    # Use midnight of the first semantic segment's date as a base,
    # offset negatively to avoid collisions with actual data points
    reference_time = json.dig('semanticSegments', 0, 'startTime')
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
