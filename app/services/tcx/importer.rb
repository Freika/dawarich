# frozen_string_literal: true

class Tcx::Importer
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader
  include Imports::ActivityTypeMapping
  include Imports::XmlAmpersandEscaping

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = Hash.from_xml(xml_content)

    activities = extract_activities(json)

    points_data = activities.flat_map { |activity| parse_activity(activity) }.compact

    points_data.each_slice(BATCH_SIZE) do |batch|
      inserted = bulk_insert_points(batch)
      broadcast_import_progress(import, inserted)
    end
  end

  private

  def xml_content
    escape_raw_ampersands(load_file_content)
  end

  def extract_activities(json)
    database = first_value(json['TrainingCenterDatabase'])
    return [] unless database.is_a?(Hash)

    Array.wrap(database['Activities']).flat_map do |container|
      container.is_a?(Hash) ? Array.wrap(container['Activity']) : []
    end
  end

  def parse_activity(activity)
    return [] unless activity.is_a?(Hash)

    sport = first_value(activity['Sport'])
    laps = Array.wrap(activity['Lap'])

    laps.flat_map { |lap| parse_lap(lap, sport) }.compact
  end

  def parse_lap(lap, sport)
    return [] unless lap.is_a?(Hash)

    tracks = Array.wrap(lap['Track'])

    tracks.flat_map { |track| parse_track(track, sport) }.compact
  end

  def parse_track(track, sport)
    return [] unless track.is_a?(Hash)

    trackpoints = Array.wrap(track['Trackpoint'])

    trackpoints.filter_map { |tp| prepare_point(tp, sport) }
  end

  def prepare_point(trackpoint, sport)
    trackpoint = first_value(trackpoint)
    return unless trackpoint.is_a?(Hash)

    position = first_value(trackpoint['Position'])
    return unless position.is_a?(Hash)

    lat = first_value(position['LatitudeDegrees'])
    lon = first_value(position['LongitudeDegrees'])
    time = first_value(trackpoint['Time'])

    return if lat.blank? || lon.blank? || time.blank?

    altitude_value = first_value(trackpoint['AltitudeMeters'])&.to_f

    attrs = {
      lonlat: "POINT(#{lon.to_d} #{lat.to_d})",
      altitude: altitude_value,
      timestamp: Time.zone.parse(time).to_i,
      velocity: extract_speed(trackpoint),
      import_id: import.id,
      user_id: user_id,
      motion_data: { 'activity_type' => map_activity_type(sport) }.compact,
      created_at: Time.current,
      updated_at: Time.current
    }
    attrs[:altitude_decimal] = altitude_value if Point.altitude_decimal_supported?
    attrs
  end

  def extract_speed(trackpoint)
    extensions = first_value(trackpoint['Extensions'])
    return unless extensions.is_a?(Hash)

    tpx = first_value(extensions['TPX'])
    speed = first_value(tpx['Speed']) if tpx.is_a?(Hash)

    speed&.to_f&.round(1)
  end

  def first_value(value)
    value.is_a?(Array) ? value.first : value
  end

  def importer_name
    'TCX'
  end
end
