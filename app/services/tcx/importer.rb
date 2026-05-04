# frozen_string_literal: true

class Tcx::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include Imports::ActivityTypeMapping

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = Hash.from_xml(load_file_content)

    activities = Array.wrap(json.dig('TrainingCenterDatabase', 'Activities', 'Activity'))

    points_data = activities.flat_map { |activity| parse_activity(activity) }.compact

    points_data.each_slice(BATCH_SIZE) do |batch|
      inserted = bulk_insert_points(batch)
      broadcast_import_progress(import, inserted)
    end
  end

  private

  def parse_activity(activity)
    return [] if activity.blank?

    sport = activity['Sport']
    laps = Array.wrap(activity['Lap'])

    laps.flat_map { |lap| parse_lap(lap, sport) }.compact
  end

  def parse_lap(lap, sport)
    tracks = Array.wrap(lap['Track'])

    tracks.flat_map { |track| parse_track(track, sport) }.compact
  end

  def parse_track(track, sport)
    trackpoints = Array.wrap(track['Trackpoint'])

    trackpoints.filter_map { |tp| prepare_point(tp, sport) }
  end

  def prepare_point(trackpoint, sport)
    return unless trackpoint.is_a?(Hash)

    position = trackpoint['Position']
    return unless position.is_a?(Hash)

    lat = position['LatitudeDegrees']
    lon = position['LongitudeDegrees']
    time = trackpoint['Time']

    return if lat.blank? || lon.blank? || time.blank?

    altitude_value = trackpoint['AltitudeMeters']&.to_f

    attrs = {
      lonlat: "POINT(#{lon.to_d} #{lat.to_d})",
      altitude: altitude_value,
      timestamp: Time.zone.parse(time).to_i,
      velocity: extract_speed(trackpoint),
      import_id: import.id,
      user_id: user_id,
      raw_data: trackpoint.merge('sport' => map_activity_type(sport)),
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
    attrs
  end

  def extract_speed(trackpoint)
    extensions = trackpoint['Extensions']
    return if extensions.blank?

    tpx = extensions['TPX']
    speed = tpx['Speed'] if tpx.is_a?(Hash)

    speed&.to_f&.round(1)
  end

  def importer_name
    'TCX'
  end
end
