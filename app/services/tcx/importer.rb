# frozen_string_literal: true

class Tcx::Importer
  include Imports::Broadcaster
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

    points_data.each_slice(BATCH_SIZE) { |batch| bulk_insert_points(batch) }
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
    position = trackpoint['Position']
    return if position.blank?

    lat = position['LatitudeDegrees']
    lon = position['LongitudeDegrees']
    time = trackpoint['Time']

    return if lat.blank? || lon.blank? || time.blank?

    {
      lonlat: "POINT(#{lon.to_d} #{lat.to_d})",
      altitude: trackpoint['AltitudeMeters']&.to_f,
      timestamp: Time.zone.parse(time).to_i,
      velocity: extract_speed(trackpoint),
      import_id: import.id,
      user_id: user_id,
      raw_data: trackpoint.merge('sport' => map_activity_type(sport)),
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def extract_speed(trackpoint)
    extensions = trackpoint['Extensions']
    return if extensions.blank?

    tpx = extensions['TPX']
    speed = tpx['Speed'] if tpx.is_a?(Hash)

    speed&.to_f&.round(1)&.to_s
  end

  def bulk_insert_points(batch)
    unique_batch = batch.uniq { |record| [record[:lonlat], record[:timestamp], record[:user_id]] }

    Point.upsert_all(
      unique_batch,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )

    broadcast_import_progress(import, unique_batch.size)
  rescue StandardError => e
    create_notification("Failed to process TCX file: #{e.message}")
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'TCX Import Error',
      content: message,
      kind: :error
    )
  end
end
