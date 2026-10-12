# frozen_string_literal: true

class DemoData::TracksSeeder
  MODE_TO_ENUM = {
    'walk'    => Track::TRANSPORTATION_MODES[:walking],
    'bike'    => Track::TRANSPORTATION_MODES[:cycling],
    'drive'   => Track::TRANSPORTATION_MODES[:driving],
    'taxi'    => Track::TRANSPORTATION_MODES[:driving],
    'highway' => Track::TRANSPORTATION_MODES[:driving],
    'fly'     => Track::TRANSPORTATION_MODES[:flying]
  }.freeze

  def initialize(user, anchor, import: nil)
    @user = user
    @anchor = anchor
    @import = import
  end

  def call(rows)
    return if rows.blank?

    rows.each do |row|
      starts = absolute(row['starts_offset_seconds'])
      ends   = absolute(row['ends_offset_seconds'])
      mode_int = MODE_TO_ENUM.fetch(row['mode'])
      avg_speed_ms = (row['avg_speed_kmh'] || 0) * 1000.0 / 3600.0
      coords = row['path_coordinates']
      next if coords.blank? || coords.length < 2

      track = @user.tracks.create!(
        start_at: starts,
        end_at: ends,
        original_path: linestring_wkt(coords),
        distance: row['distance_meters'],
        avg_speed: avg_speed_ms.round(3),
        duration: row['duration_seconds'],
        elevation_gain: 0,
        elevation_loss: 0,
        elevation_max: 0,
        elevation_min: 0,
        dominant_mode: mode_int,
        tracker_id: 'demo',
        demo: true
      )

      track.track_segments.create!(
        transportation_mode: mode_int,
        start_index: 0,
        end_index: [coords.length - 1, 0].max,
        distance: row['distance_meters'].to_i,
        duration: row['duration_seconds'].to_i,
        avg_speed: row['avg_speed_kmh'].to_f,
        max_speed: row['avg_speed_kmh'].to_f * 1.2,
        confidence: :high
      )

      scope = Point.where(user_id: @user.id, track_id: nil, timestamp: starts.to_i...ends.to_i)
      scope = scope.where(import_id: @import.id) if @import
      scope.update_all(track_id: track.id)
    end
  end

  private

  def absolute(offset_seconds)
    Time.zone.at(@anchor.to_i + offset_seconds.to_i)
  end

  def linestring_wkt(coords)
    parts = coords.map { |lat, lon| "#{lon} #{lat}" }.join(', ')
    "SRID=4326;LINESTRING(#{parts})"
  end
end
