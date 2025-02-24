# frozen_string_literal: true

class Gpx::TrackImporter
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

    points = tracks_arr.map { parse_track(_1) }.flatten.compact
    points_data = points.map.with_index(1) { |point, index| prepare_point(point, index) }.compact

    bulk_insert_points(points_data)
  end

  private

  def parse_track(track)
    return if track['trkseg'].blank?

    segments = track['trkseg']
    segments_array = segments.is_a?(Array) ? segments : [segments]

    segments_array.compact.map { |segment| segment['trkpt'] }
  end

  def prepare_point(point, index)
    return if point['lat'].blank? || point['lon'].blank? || point['time'].blank?

    {
      lonlat: "POINT(#{point['lon'].to_d} #{point['lat'].to_d})",
      altitude: point['ele'].to_i,
      timestamp: Time.parse(point['time']).to_i,
      import_id: import.id,
      velocity: speed(point),
      raw_data: point,
      user_id: user_id,
      created_at: Time.current,
      updated_at: Time.current
    }
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

    broadcast_import_progress(import, unique_batch.size)
  rescue StandardError => e
    create_notification("Failed to process GPX track: #{e.message}")
  end

  def create_notification(message)
    Notification.create!(
      user_id: user_id,
      title: 'GPX Import Error',
      content: message,
      kind: :error
    )
  end

  def speed(point)
    return if point['extensions'].blank?

    (
      point.dig('extensions', 'speed') || point.dig('extensions', 'TrackPointExtension', 'speed')
    ).to_f.round(1)
  end
end
