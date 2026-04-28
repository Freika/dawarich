# frozen_string_literal: true

require 'rexml/document'

class Gpx::TrackImporter
  include Imports::Broadcaster
  include Imports::BulkInsertable
  include Imports::FileLoader

  BATCH_SIZE = 1000

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    file_content = load_file_content
    json = Hash.from_xml(file_content)

    tracks = json['gpx']['trk']
    tracks_arr = tracks.is_a?(Array) ? tracks : [tracks]

    points = tracks_arr.map { parse_track(_1) }.flatten.compact
    points_data = points.map { prepare_point(_1) }.compact

    points_data.each_slice(BATCH_SIZE) do |batch|
      inserted = bulk_insert_points(batch)
      broadcast_import_progress(import, inserted)
    end
  end

  private

  def parse_track(track)
    return if track['trkseg'].blank?

    segments = track['trkseg']
    segments_array = segments.is_a?(Array) ? segments : [segments]

    segments_array.compact.map { |segment| segment['trkpt'] }
  end

  def prepare_point(point)
    return if point['lat'].blank? || point['lon'].blank? || point['time'].blank?

    elevation = point['ele'].to_f

    {
      lonlat: "POINT(#{point['lon'].to_d} #{point['lat'].to_d})",
      # During the integer→decimal altitude migration we write to both
      # columns; readers (`Point#altitude`) prefer altitude_decimal.
      altitude: elevation,
      altitude_decimal: elevation,
      timestamp: Time.zone.parse(point['time']).utc.to_i,
      import_id: import.id,
      velocity: speed(point),
      raw_data: point,
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def importer_name
    'GPX'
  end

  def speed(point)
    return if point['extensions'].blank?

    value = point.dig('extensions', 'speed')
    extensions = point.dig('extensions', 'TrackPointExtension')
    value ||= extensions.is_a?(Hash) ? extensions['speed'] : nil

    value&.to_f&.round(1)
  end
end
