# frozen_string_literal: true

class Gpx::TrackParser
  attr_reader :import, :json, :user_id

  def initialize(import, user_id)
    @import = import
    @json = import.raw_data
    @user_id = user_id
  end

  def call
    tracks = json['gpx']['trk']
    tracks_arr = tracks.is_a?(Array) ? tracks : [tracks]

    tracks_arr.map { parse_track(_1) }.flatten
  end

  private

  def parse_track(track)
    segments = track['trkseg']
    segments_array = segments.is_a?(Array) ? segments : [segments]

    segments_array.map do |segment|
      segment['trkpt'].each { create_point(_1) }
    end
  end

  def create_point(point)
    return if point['lat'].blank? || point['lon'].blank? || point['time'].blank?
    return if point_exists?(point)

    Point.create(
      latitude:   point['lat'].to_d,
      longitude:  point['lon'].to_d,
      altitude:   point['ele'].to_i,
      timestamp:  Time.parse(point['time']).to_i,
      import_id:  import.id,
      raw_data: point,
      user_id:
    )
  end

  def point_exists?(point)
    Point.exists?(
      latitude:   point['lat'].to_d,
      longitude:  point['lon'].to_d,
      timestamp:  Time.parse(point['time']).to_i,
      user_id:
    )
  end
end
