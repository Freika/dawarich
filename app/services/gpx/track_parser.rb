# frozen_string_literal: true

class Gpx::TrackParser
  include Imports::Broadcaster

  attr_reader :import, :json, :user_id

  def initialize(import, user_id)
    @import = import
    @json = import.raw_data
    @user_id = user_id
  end

  def call
    tracks = json['gpx']['trk']
    tracks_arr = tracks.is_a?(Array) ? tracks : [tracks]

    tracks_arr.map { parse_track(_1) }.flatten.each.with_index(1) do |point, index|
      create_point(point, index)
    end
  end

  private

  def parse_track(track)
    segments = track['trkseg']
    segments_array = segments.is_a?(Array) ? segments : [segments]

    segments_array.map { |segment| segment['trkpt'] }
  end

  def create_point(point, index)
    return if point['lat'].blank? || point['lon'].blank? || point['time'].blank?
    return if point_exists?(point)

    Point.create(
      latitude:   point['lat'].to_d,
      longitude:  point['lon'].to_d,
      altitude:   point['ele'].to_i,
      timestamp:  Time.parse(point['time']).to_i,
      import_id:  import.id,
      velocity:   speed(point),
      raw_data: point,
      user_id:
    )

    broadcast_import_progress(import, index)
  end

  def point_exists?(point)
    Point.exists?(
      latitude:   point['lat'].to_d,
      longitude:  point['lon'].to_d,
      timestamp:  Time.parse(point['time']).to_i,
      user_id:
    )
  end

  def speed(point)
    return if point['extensions'].blank?

    point.dig('extensions', 'speed').to_f || point.dig('extensions', 'TrackPointExtension', 'speed').to_f
  end
end
