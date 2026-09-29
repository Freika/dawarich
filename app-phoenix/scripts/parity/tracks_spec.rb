# frozen_string_literal: true

require 'rails_helper'

class TracksFixtureBuilder
  include Tracks::TrackBuilder

  attr_reader :user

  def initialize(user)
    @user = user
  end
end

module TracksFixtureOracle
  LON = 12.3731
  LAT = 51.3397

  TRANSPORT_TRACK_NAMES = %i[
    walk_drive_walk cycling flying train_highway_tie sparse degenerate overland_hints google_hints calibrator_kmh
  ].freeze
end

RSpec.describe 'Phoenix fixture: track generation as Rails computes it' do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      entries = value.map { |v| "#{pad}#{exact_json(v, depth + 1)}" }
      "[\n#{entries.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def plain(value)
    case value
    when ActiveSupport::TimeWithZone, DateTime, Time then value.to_i
    when BigDecimal then value.to_s('F')
    when Hash then value.to_h { |k, v| [k.to_s, plain(v)] }
    when Array then value.map { |v| plain(v) }
    when Symbol then value.to_s
    else value
    end
  end

  def write_fixture(name, data)
    path = Rails.root.join("app-phoenix/test/fixtures/tracks/#{name}.json")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{exact_json(plain(data))}\n")
  end

  def coord(index, lon_step: 0.0008, lat_step: 0.0005)
    [(TracksFixtureOracle::LON + (index * lon_step)).round(6), (TracksFixtureOracle::LAT + (index * lat_step)).round(6)]
  end

  def berlin_time(year, month, day, hour = 0, minute = 0)
    ActiveSupport::TimeZone['Europe/Berlin'].local(year, month, day, hour, minute)
  end

  def make_point(user:, time:, lon:, lat:, tracker_id: nil, altitude: nil, altitude_decimal: :unset, velocity: nil,
                 accuracy: nil, motion_data: {}, source_id: nil, import_id: nil, track_id: nil, created_at: :unset)
    point = create(:point, user: user, tracker_id: tracker_id, source_id: source_id, timestamp: time.to_i,
                           lonlat: "POINT(#{lon} #{lat})", altitude: altitude, velocity: velocity,
                           accuracy: accuracy, motion_data: motion_data, import_id: import_id, track_id: track_id)
    overrides = { created_at: created_at == :unset ? time : created_at }
    overrides[:altitude_decimal] = altitude_decimal unless altitude_decimal == :unset
    point.update_columns(overrides)
    point.reload
  end

  def make_point_source(tracker_id)
    PointSource.create!(tracker_id: tracker_id, digest: Digest::MD5.hexdigest("fixture:#{tracker_id}"))
  end

  def build_track!(user:, tracker_id:, start_at:, end_at:, import_id: nil, distance: 100, avg_speed: 3.6,
                   duration: 300)
    lon2 = TracksFixtureOracle::LON + 0.001
    lat2 = TracksFixtureOracle::LAT + 0.001
    Track.create!(user: user, tracker_id: tracker_id, start_at: start_at, end_at: end_at,
                  original_path: "LINESTRING(#{TracksFixtureOracle::LON} #{TracksFixtureOracle::LAT}, #{lon2} #{lat2})",
                  distance: distance, avg_speed: avg_speed, duration: duration, elevation_gain: 0,
                  elevation_loss: 0, elevation_max: 0, elevation_min: 0, import_id: import_id)
  end

  def remap_id(scope, real_id)
    return nil if real_id.nil?

    @id_remap ||= Hash.new { |h, k| h[k] = {} }
    table = @id_remap[scope]
    table[real_id] ||= table.size + 1
  end

  def seed_remap!(scope, ids)
    ids.compact.uniq.sort.each { |id| remap_id(scope, id) }
  end

  def remap_point_id_rows(rows)
    rows.map { |row| row.merge(point_id: remap_id(:points, row[:point_id])) }
  end

  def remap_point_ids_windows(windows)
    windows.map { |window| window.merge(point_ids: window[:point_ids].map { |id| remap_id(:points, id) }) }
  end

  def dump_user(user)
    { id: remap_id(:users, user.id), settings: user.settings }
  end

  def dump_point_source(source)
    { id: remap_id(:point_sources, source.id), tracker_id: source.tracker_id }
  end

  def dump_import(import)
    { id: remap_id(:imports, import.id), user_id: remap_id(:users, import.user_id),
      status: Import.statuses[import.status], source: import.source && Import.sources[import.source],
      additional_data_extraction_status: Import.additional_data_extraction_statuses[
        import.additional_data_extraction_status
      ] }
  end

  def dump_point(point)
    record = Point.find(point.id)
    wkt = Point.connection.select_value("SELECT ST_AsText(lonlat) FROM points WHERE id = #{record.id.to_i}")
    { id: remap_id(:points, record.id), timestamp: record.timestamp, lonlat_wkt: wkt, lon: record.lon,
      lat: record.lat, track_id: remap_id(:tracks, record.track_id), altitude: record[:altitude],
      altitude_decimal: record.altitude_decimal, tracker_id: record[:tracker_id],
      source_id: remap_id(:point_sources, record.source_id), user_id: remap_id(:users, record.user_id),
      anomaly: record.anomaly, import_id: remap_id(:imports, record.import_id), velocity: record.velocity,
      accuracy: record.accuracy, motion_data: record.motion_data, created_at: record.created_at }
  end

  def dump_track(track)
    record = Track.find(track.id)
    wkt = Track.connection.select_value("SELECT ST_AsText(original_path) FROM tracks WHERE id = #{record.id.to_i}")
    { id: remap_id(:tracks, record.id), user_id: remap_id(:users, record.user_id), tracker_id: record.tracker_id,
      start_at: record.start_at, end_at: record.end_at, original_path_wkt: wkt, distance: record.distance,
      duration: record.duration, avg_speed: record.avg_speed, elevation_gain: record.elevation_gain,
      elevation_loss: record.elevation_loss, elevation_max: record.elevation_max, elevation_min: record.elevation_min,
      dominant_mode: Track.dominant_modes[record.dominant_mode], import_id: remap_id(:imports, record.import_id) }
  end

  def dump_segment_fields(segment)
    wkt = segment.path && TrackSegment.connection.select_value(
      "SELECT ST_AsText(path) FROM track_segments WHERE id = #{segment.id.to_i}"
    )
    { transportation_mode: TrackSegment.transportation_modes[segment.transportation_mode],
      start_at: segment.start_at, end_at: segment.end_at, start_index: segment.start_index,
      end_index: segment.end_index, path_wkt: wkt, distance: segment.distance, duration: segment.duration,
      avg_speed: segment.avg_speed, max_speed: segment.max_speed,
      confidence: TrackSegment.confidences[segment.confidence], confidence_score: segment.confidence_score,
      source: segment.source, corrected_at: segment.corrected_at }
  end

  def dump_segment_input(segment)
    dump_segment_fields(segment).merge(id: remap_id(:track_segments, segment.id),
                                       track_id: remap_id(:tracks, segment.track_id))
  end

  def dump_segment_expected(segment)
    dump_segment_fields(segment).merge(track: track_identity(Track.find(segment.track_id)))
  end

  def track_identity(track)
    { tracker_id: track.tracker_id, start_at: track.start_at, end_at: track.end_at }
  end

  def empty_input
    { users: [], point_sources: [], imports: [], points: [], tracks: [], track_segments: [] }
  end

  def dump_all_tracks_and_segments(user)
    tracks = Track.where(user_id: user.id).order(:id).to_a
    seed_remap!(:tracks, tracks.map(&:id))
    segments = TrackSegment.where(track_id: tracks.map(&:id)).order(:id).to_a
    seed_remap!(:track_segments, segments.map(&:id))
    ordered_tracks = tracks.sort_by { |t| [t.start_at, t.id] }
    { tracks: ordered_tracks.map { |t| dump_track(t) }, track_segments: segments.map { |s| dump_segment_expected(s) } }
  end

  def point_track_map(points)
    points.map do |point|
      record = Point.find(point.id)
      track = record.track_id && Track.find_by(id: record.track_id)
      { id: remap_id(:points, record.id), timestamp: record.timestamp, track: track && track_identity(track) }
    end
  end

  def capture_track_events(known = {})
    events = []
    identity = known.dup
    allow(TracksChannel).to receive(:broadcast_to) do |_user, payload|
      case payload[:action]
      when 'created', 'updated'
        id = payload[:track][:id]
        track = Track.find_by(id: id)
        identity[id] = track_identity(track) if track
        events << { action: payload[:action], track: identity[id] }
      when 'destroyed'
        events << { action: 'destroyed', track: identity[payload[:track_id]] }
      end
    end
    result = yield
    [events, result]
  end

  def build_phases(start_lon, start_lat, phases)
    rows = []
    offset = 0
    lon = start_lon
    lat = start_lat
    phases.each do |phase|
      phase[:count].times do
        rows << { offset: offset, lon: lon.round(6), lat: lat.round(6), velocity: phase[:velocity],
                  accuracy: phase[:accuracy] || 5, motion_data: phase[:motion_data] || {} }
        lon += phase[:lon_step]
        lat += phase[:lat_step]
        offset += phase[:dt]
      end
    end
    rows
  end

  def transport_track_spec(name)
    lon = TracksFixtureOracle::LON
    lat = TracksFixtureOracle::LAT
    case name
    when :walk_drive_walk
      build_phases(lon, lat, [
                     { count: 4, dt: 60, velocity: '1.3', lon_step: 0.00001, lat_step: 0.00001 },
                     { count: 5, dt: 30, velocity: '25.0', lon_step: 0.0003, lat_step: 0.0001 },
                     { count: 4, dt: 60, velocity: '1.3', lon_step: 0.00001, lat_step: 0.00001 }
                   ])
    when :cycling
      build_phases(lon, lat, [{ count: 8, dt: 30, velocity: '5.5', lon_step: 0.00006, lat_step: 0.00002 }])
    when :flying
      build_phases(lon, lat, [{ count: 6, dt: 300, velocity: '230.0', lon_step: 0.03, lat_step: 0.01 }])
    when :train_highway_tie
      build_phases(lon, lat, [{ count: 8, dt: 20, velocity: nil, lon_step: 0.00862, lat_step: 0.0 }])
    when :sparse
      build_phases(lon, lat, [{ count: 8, dt: 90, velocity: '1.3', lon_step: 0.00001, lat_step: 0.00001 }])
    when :degenerate
      build_phases(lon, lat, [{ count: 2, dt: 10, velocity: '1.0', lon_step: 0.00001, lat_step: 0.00001 }])
    when :overland_hints
      build_phases(lon, lat, [{ count: 6, dt: 30, velocity: '1.3', lon_step: 0.00001, lat_step: 0.00001,
                                 motion_data: { 'motion' => ['driving'] } }])
    when :google_hints
      build_phases(lon, lat, [{ count: 6, dt: 30, velocity: nil, lon_step: 0.00862, lat_step: 0.0,
                                 motion_data: { 'activityType' => 'IN_VEHICLE' } }])
    when :calibrator_kmh
      build_phases(lon, lat, [{ count: 25, dt: 30, velocity: '36.0', lon_step: 0.00432, lat_step: 0.0 }])
    end
  end

  def haversine_distance_m(lat1, lon1, lat2, lon2)
    rad = ->(deg) { deg * (Math::PI / 180) }
    a1 = rad.call(lat1)
    o1 = rad.call(lon1)
    a2 = rad.call(lat2)
    o2 = rad.call(lon2)
    a = (Math.sin((a2 - a1) / 2)**2) + (Math.cos(a1) * (Math.sin((o2 - o1) / 2)**2) * Math.cos(a2))
    2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 6371.0 * 1000
  end

  it 'writes range_dst.json' do
    user = create(:user)
    device = 'device-dst'
    schedule = [
      [2026, 3, 28, 22, 0], [2026, 3, 28, 22, 20], [2026, 3, 28, 22, 40],
      [2026, 3, 28, 23, 0], [2026, 3, 28, 23, 20], [2026, 3, 28, 23, 40],
      [2026, 3, 29, 0, 0], [2026, 3, 29, 0, 20], [2026, 3, 29, 0, 40],
      [2026, 3, 29, 1, 0], [2026, 3, 29, 1, 20], [2026, 3, 29, 1, 40],
      [2026, 3, 29, 3, 10], [2026, 3, 29, 3, 30], [2026, 3, 29, 3, 50],
      [2026, 3, 29, 4, 10], [2026, 3, 29, 9, 0], [2026, 3, 29, 9, 20],
      [2026, 3, 29, 9, 40], [2026, 3, 29, 10, 0],
      [2026, 3, 30, 23, 20], [2026, 3, 30, 23, 40], [2026, 3, 31, 0, 0], [2026, 3, 31, 0, 20]
    ]
    points = schedule.each_with_index.map do |(y, m, d, h, mi), i|
      lon, lat = coord(i)
      make_point(user: user, tracker_id: device, time: berlin_time(y, m, d, h, mi), lon: lon, lat: lat,
                 altitude: 100 + i, velocity: '1.3', accuracy: 5)
    end

    boundary_device = 'device-boundary'
    boundary_start = berlin_time(2026, 3, 28, 16, 0)
    boundary_points = 49.times.map do |i|
      lon, lat = coord(i + 100)
      make_point(user: user, tracker_id: boundary_device, time: boundary_start + (i * 20).minutes, lon: lon,
                 lat: lat, altitude: 50, velocity: '1.3', accuracy: 5)
    end

    refresh_device = 'device-refresh'
    refresh_import = create(:import, user: user, name: 'refresh.gpx', source: :gpx)
    rp1_lon, rp1_lat = coord(200)
    rp2_lon, rp2_lat = coord(201)
    refresh_p1 = make_point(user: user, tracker_id: refresh_device, time: berlin_time(2026, 3, 28, 10, 0),
                            lon: rp1_lon, lat: rp1_lat, altitude: 50)
    refresh_p2 = make_point(user: user, tracker_id: refresh_device, time: berlin_time(2026, 3, 28, 10, 10),
                            lon: rp2_lon, lat: rp2_lat, altitude: 50)
    refresh_track = build_track!(user: user, tracker_id: refresh_device, start_at: refresh_p1.recorded_at,
                                 end_at: refresh_p1.recorded_at, import_id: refresh_import.id)
    Point.where(id: [refresh_p1.id, refresh_p2.id]).update_all(track_id: refresh_track.id)

    points += boundary_points + [refresh_p1, refresh_p2]

    seed_remap!(:tracks, [refresh_track.id])
    input = empty_input.merge(users: [dump_user(user)], imports: [dump_import(refresh_import)],
                              tracks: [dump_track(refresh_track)], points: points.map { |p| dump_point(p) })

    start_at = berlin_time(2026, 3, 28)
    end_at = berlin_time(2026, 3, 31)
    calls = [{ service: 'Tracks::ParallelGenerator', start_at: start_at, end_at: end_at, zone: 'Europe/Berlin',
               mode: 'bulk', untracked_only: false, import_id: nil }]

    known = { refresh_track.id => track_identity(refresh_track) }
    session = nil
    events, = capture_track_events(known) do
      perform_enqueued_jobs do
        session = Tracks::ParallelGenerator.new(user, start_at: start_at, end_at: end_at, mode: :bulk).call
      end
    end

    refresh_result = session.get_session_data.dig('metadata', 'track_metadata_refresh')

    write_fixture('range_dst', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events, track_metadata_refresh: refresh_result
    ), call: calls })
  end

  it 'writes range_two_trackers.json' do
    user = create(:user)
    base = berlin_time(2026, 4, 6, 8, 0)
    source_b = make_point_source('device-b')

    a_points = 10.times.map do |i|
      lon, lat = coord(i, lon_step: 0.0006, lat_step: 0.0004)
      make_point(user: user, tracker_id: 'device-a', time: base + (i * 5).minutes, lon: lon, lat: lat,
                 altitude: 90, velocity: '1.2', accuracy: 5)
    end
    gap1_lon, gap1_lat = coord(20, lon_step: 0.0006, lat_step: 0.0004)
    gap2_lon, gap2_lat = coord(21, lon_step: 0.0006, lat_step: 0.0004)
    a_points << make_point(user: user, tracker_id: 'device-a', time: base + 10.hours, lon: gap1_lon, lat: gap1_lat,
                           altitude: 90, velocity: '1.2', accuracy: 5)
    a_points << make_point(user: user, tracker_id: 'device-a', time: base + 10.hours + 5.minutes, lon: gap2_lon,
                           lat: gap2_lat, altitude: 90, velocity: '1.2', accuracy: 5)

    b_points = 10.times.map do |i|
      lon, lat = coord(i, lon_step: -0.0007, lat_step: 0.0009)
      make_point(user: user, source_id: source_b.id, time: base + 150 + (i * 300), lon: lon, lat: lat,
                 altitude: 150, velocity: '4.5', accuracy: 6)
    end

    points = a_points + b_points
    input = empty_input.merge(users: [dump_user(user)], point_sources: [dump_point_source(source_b)],
                              points: points.map { |p| dump_point(p) })

    start_at = base - 1.hour
    end_at = base + 12.hours
    calls = [{ service: 'Tracks::ParallelGenerator', start_at: start_at, end_at: end_at, zone: 'Europe/Berlin',
               mode: 'bulk', untracked_only: false, import_id: nil }]

    events, = capture_track_events do
      perform_enqueued_jobs do
        Tracks::ParallelGenerator.new(user, start_at: start_at, end_at: end_at, mode: :bulk).call
      end
    end

    write_fixture('range_two_trackers', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events
    ), call: calls })
  end

  it 'writes range_q2.json' do
    user = create(:user)
    base = berlin_time(2026, 5, 4, 8, 0)
    import_pending = create(:import, user: user, name: 'pending.gpx', source: :gpx, status: :processing,
                                      additional_data_extraction_status: :not_attempted)
    import_terminal = create(:import, user: user, name: 'terminal.gpx', source: :gpx, status: :completed,
                                       additional_data_extraction_status: :completed)

    pending_points = 4.times.map do |i|
      lon, lat = coord(i)
      make_point(user: user, tracker_id: 'device-q2', import_id: import_pending.id, time: base + (i * 10).minutes,
                 lon: lon, lat: lat, altitude: 100)
    end
    terminal_points = 4.times.map do |i|
      lon, lat = coord(i + 10)
      make_point(user: user, tracker_id: 'device-q2', import_id: import_terminal.id,
                 time: base + 2.hours + (i * 10).minutes, lon: lon, lat: lat, altitude: 100)
    end
    ordinary_points = 4.times.map do |i|
      lon, lat = coord(i + 20)
      make_point(user: user, tracker_id: 'device-q2', time: base + 4.hours + (i * 10).minutes, lon: lon, lat: lat,
                 altitude: 100)
    end

    points = pending_points + terminal_points + ordinary_points
    input = empty_input.merge(
      users: [dump_user(user)], imports: [dump_import(import_pending), dump_import(import_terminal)],
      points: points.map { |p| dump_point(p) }
    )

    daily_start = base - 1.hour
    daily_end = base + 6.hours
    pending_min_ts, pending_max_ts = pending_points.map(&:timestamp).minmax
    scoped_start = Time.zone.at(pending_min_ts)
    scoped_end = Time.zone.at(pending_max_ts)
    calls = [
      { service: 'Tracks::ParallelGenerator', start_at: daily_start, end_at: daily_end,
        zone: daily_start.time_zone.name, mode: 'daily', untracked_only: false, import_id: nil },
      { service: 'Tracks::ParallelGenerator', start_at: scoped_start, end_at: scoped_end,
        zone: scoped_start.time_zone.name, mode: 'bulk', untracked_only: true,
        import_id: remap_id(:imports, import_pending.id) }
    ]

    events, = capture_track_events do
      perform_enqueued_jobs do
        Tracks::ParallelGenerator.new(user, start_at: daily_start, end_at: daily_end, mode: :daily).call
        Tracks::ParallelGenerator.new(user, start_at: scoped_start, end_at: scoped_end, mode: :bulk,
                                             untracked_only: true, import_id: import_pending.id).call
      end
    end

    write_fixture('range_q2', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events
    ), call: calls })
  end

  it 'writes range_kept.json' do
    user = create(:user)
    base = berlin_time(2026, 6, 1, 8, 0)
    import = create(:import, user: user, name: 'kept.gpx', source: :gpx)

    k1_points = 3.times.map do |i|
      lon, lat = coord(i)
      make_point(user: user, tracker_id: 'device-k1', time: base + (i * 10).minutes, lon: lon, lat: lat, altitude: 80)
    end
    k1 = build_track!(user: user, tracker_id: 'device-k1', start_at: k1_points.first.recorded_at,
                      end_at: k1_points.last.recorded_at, import_id: import.id)
    Point.where(id: k1_points.map(&:id)).update_all(track_id: k1.id)

    k2_points = 3.times.map do |i|
      lon, lat = coord(i + 10)
      make_point(user: user, tracker_id: 'device-k2', time: base + 1.hour + (i * 10).minutes, lon: lon, lat: lat,
                 altitude: 80)
    end
    k2 = build_track!(user: user, tracker_id: 'device-k2', start_at: k2_points.first.recorded_at,
                      end_at: k2_points.last.recorded_at)
    Point.where(id: k2_points.map(&:id)).update_all(track_id: k2.id)
    corrected_segment = TrackSegment.create!(track: k2, transportation_mode: :walking, corrected_at: base - 1.day,
                                             start_at: k2.start_at, end_at: k2.end_at, distance: 10, duration: 600,
                                             avg_speed: 1.0, max_speed: 1.5, confidence: :high, source: 'manual')

    d1_points = 3.times.map do |i|
      lon, lat = coord(i + 20)
      make_point(user: user, tracker_id: 'device-d1', time: base + 2.hours + (i * 10).minutes, lon: lon, lat: lat,
                 altitude: 80)
    end
    d1 = build_track!(user: user, tracker_id: 'device-d1', start_at: d1_points.first.recorded_at,
                      end_at: d1_points.last.recorded_at)
    Point.where(id: d1_points.map(&:id)).update_all(track_id: d1.id)

    points = k1_points + k2_points + d1_points
    seed_remap!(:tracks, [k1.id, k2.id, d1.id])
    input = empty_input.merge(
      users: [dump_user(user)], imports: [dump_import(import)],
      tracks: [k1, k2, d1].map { |t| dump_track(t) }, track_segments: [dump_segment_input(corrected_segment)],
      points: points.map { |p| dump_point(p) }
    )

    start_at = base - 1.hour
    end_at = base + 4.hours
    calls = [{ service: 'Tracks::ParallelGenerator', start_at: start_at, end_at: end_at, zone: 'Europe/Berlin',
               mode: 'bulk', untracked_only: false, import_id: nil }]

    known = { k1.id => track_identity(k1), k2.id => track_identity(k2), d1.id => track_identity(d1) }
    events, = capture_track_events(known) do
      perform_enqueued_jobs do
        Tracks::ParallelGenerator.new(user, start_at: start_at, end_at: end_at, mode: :bulk).call
      end
    end

    write_fixture('range_kept', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events
    ), call: calls })
  end

  it 'writes range_orphans.json' do
    user = create(:user)
    import = create(:import, user: user, name: 'orphans.gpx', source: :gpx)
    base = berlin_time(2026, 7, 1, 8, 0)

    e_lon, e_lat = coord(0)
    e_point = make_point(user: user, tracker_id: 'device-e', time: base, lon: e_lon, lat: e_lat, altitude: 60)
    e_track = build_track!(user: user, tracker_id: 'device-e', start_at: e_point.recorded_at,
                           end_at: e_point.recorded_at, import_id: import.id)
    e_point.update!(track_id: e_track.id)
    s_lon, s_lat = coord(1)
    singleton = make_point(user: user, tracker_id: 'device-e', time: base + 5.minutes, lon: s_lon, lat: s_lat,
                           altitude: 60)

    fb_lon, fb_lat = coord(10)
    fa_lon, fa_lat = coord(13)
    f_before = make_point(user: user, tracker_id: 'device-f', time: base + 1.hour, lon: fb_lon, lat: fb_lat,
                          altitude: 60)
    f_after = make_point(user: user, tracker_id: 'device-f', time: base + 1.hour + 20.minutes, lon: fa_lon, lat: fa_lat,
                         altitude: 60)
    f_track = build_track!(user: user, tracker_id: 'device-f', start_at: f_before.recorded_at,
                           end_at: f_after.recorded_at, import_id: import.id)
    Point.where(id: [f_before.id, f_after.id]).update_all(track_id: f_track.id)
    m1_lon, m1_lat = coord(11)
    m2_lon, m2_lat = coord(12)
    mid1 = make_point(user: user, tracker_id: 'device-f', time: base + 1.hour + 7.minutes, lon: m1_lon, lat: m1_lat,
                      altitude: 60)
    mid2 = make_point(user: user, tracker_id: 'device-f', time: base + 1.hour + 13.minutes, lon: m2_lon, lat: m2_lat,
                      altitude: 60)

    points = [e_point, singleton, f_before, mid1, mid2, f_after]
    seed_remap!(:points, points.map(&:id))
    seed_remap!(:tracks, [e_track.id, f_track.id])
    input = empty_input.merge(users: [dump_user(user)], imports: [dump_import(import)],
                              tracks: [e_track, f_track].map { |t| dump_track(t) },
                              points: points.map { |p| dump_point(p) })

    start_at = base - 1.hour
    end_at = base + 3.hours
    calls = [{ service: 'Tracks::ParallelGenerator', start_at: start_at, end_at: end_at, zone: 'Europe/Berlin',
               mode: 'bulk', untracked_only: false, import_id: nil }]

    known = { e_track.id => track_identity(e_track), f_track.id => track_identity(f_track) }
    events, = capture_track_events(known) do
      perform_enqueued_jobs do
        Tracks::ParallelGenerator.new(user, start_at: start_at, end_at: end_at, mode: :bulk).call
      end
    end

    write_fixture('range_orphans', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events
    ), call: calls })
  end

  it 'writes range_untracked_only.json' do
    user = create(:user)
    base = berlin_time(2026, 1, 15, 8, 0)

    g_points = 3.times.map do |i|
      lon, lat = coord(i)
      make_point(user: user, tracker_id: 'device-g', time: base + (i * 10).minutes, lon: lon, lat: lat, altitude: 60)
    end
    g_track = build_track!(user: user, tracker_id: 'device-g', start_at: g_points.first.recorded_at,
                           end_at: g_points.last.recorded_at)
    Point.where(id: g_points.map(&:id)).update_all(track_id: g_track.id)

    hb_lon, hb_lat = coord(10)
    ha_lon, ha_lat = coord(13)
    h_before = make_point(user: user, tracker_id: 'device-h', time: base + 1.hour, lon: hb_lon, lat: hb_lat,
                          altitude: 60)
    h_after = make_point(user: user, tracker_id: 'device-h', time: base + 1.hour + 20.minutes, lon: ha_lon,
                         lat: ha_lat, altitude: 60)
    h_track = build_track!(user: user, tracker_id: 'device-h', start_at: h_before.recorded_at,
                           end_at: h_after.recorded_at)
    Point.where(id: [h_before.id, h_after.id]).update_all(track_id: h_track.id)
    hm1_lon, hm1_lat = coord(11)
    hm2_lon, hm2_lat = coord(12)
    h_mid1 = make_point(user: user, tracker_id: 'device-h', time: base + 1.hour + 7.minutes, lon: hm1_lon,
                        lat: hm1_lat, altitude: 60)
    h_mid2 = make_point(user: user, tracker_id: 'device-h', time: base + 1.hour + 13.minutes, lon: hm2_lon,
                        lat: hm2_lat, altitude: 60)

    it_lon, it_lat = coord(20)
    is_lon, is_lat = coord(21)
    i_tracked = make_point(user: user, tracker_id: 'device-i', time: base + 2.hours, lon: it_lon, lat: it_lat,
                           altitude: 60)
    i_track = build_track!(user: user, tracker_id: 'device-i', start_at: i_tracked.recorded_at,
                           end_at: i_tracked.recorded_at)
    i_tracked.update!(track_id: i_track.id)
    i_singleton = make_point(user: user, tracker_id: 'device-i', time: base + 2.hours + 5.minutes, lon: is_lon,
                             lat: is_lat, altitude: 60)

    j1_lon, j1_lat = coord(30)
    j2_lon, j2_lat = coord(31)
    j3_lon, j3_lat = coord(32)
    j_points = [
      make_point(user: user, tracker_id: 'device-j', time: base + 2.hours + 30.minutes, lon: j1_lon, lat: j1_lat,
                 altitude: 60),
      make_point(user: user, tracker_id: 'device-j', time: base + 2.hours + 40.minutes, lon: j2_lon, lat: j2_lat,
                 altitude: 60),
      make_point(user: user, tracker_id: 'device-j', time: base + 2.hours + 50.minutes, lon: j3_lon, lat: j3_lat,
                 altitude: 60)
    ]

    points = g_points + [h_before, h_mid1, h_mid2, h_after, i_tracked, i_singleton] + j_points
    seed_remap!(:points, points.map(&:id))
    seed_remap!(:tracks, [g_track.id, h_track.id, i_track.id])
    input = empty_input.merge(users: [dump_user(user)],
                              tracks: [g_track, h_track, i_track].map { |t| dump_track(t) },
                              points: points.map { |p| dump_point(p) })

    start_at = base - 1.hour
    end_at = base + 3.hours
    calls = [{ service: 'Tracks::ParallelGenerator', start_at: start_at, end_at: end_at, zone: 'Europe/Berlin',
               mode: 'bulk', untracked_only: true, import_id: nil }]

    known = { g_track.id => track_identity(g_track), h_track.id => track_identity(h_track),
              i_track.id => track_identity(i_track) }
    events, = capture_track_events(known) do
      perform_enqueued_jobs do
        Tracks::ParallelGenerator.new(user, start_at: start_at, end_at: end_at, mode: :bulk,
                                             untracked_only: true).call
      end
    end

    write_fixture('range_untracked_only', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events
    ), call: calls })
  end

  it 'writes realtime.json' do
    user = create(:user)
    reference = Time.utc(2026, 8, 1, 12, 0, 0)
    travel_to(reference) do
      p0_lon, p0_lat = coord(0)
      p1_lon, p1_lat = coord(1)
      preceding = build_track!(user: user, tracker_id: 'device-rt', start_at: reference - 5.hours,
                               end_at: reference - 4.hours - 40.minutes)
      p_pre_a = make_point(user: user, tracker_id: 'device-rt', time: reference - 5.hours, lon: p0_lon, lat: p0_lat,
                           altitude: 70)
      p_pre_b = make_point(user: user, tracker_id: 'device-rt', time: reference - 4.hours - 40.minutes, lon: p1_lon,
                           lat: p1_lat, altitude: 70)
      Point.where(id: [p_pre_a.id, p_pre_b.id]).update_all(track_id: preceding.id)

      orphan_lon, orphan_lat = coord(2)
      orphan = make_point(user: user, tracker_id: 'device-rt', time: reference - 4.hours - 50.minutes,
                          lon: orphan_lon, lat: orphan_lat, altitude: 70, created_at: reference - 5.minutes)

      seg1 = 5.times.map do |i|
        lon, lat = coord(i + 10)
        make_point(user: user, tracker_id: 'device-rt', time: reference - 4.hours - 15.minutes + (i * 5).minutes,
                   lon: lon, lat: lat, altitude: 70)
      end
      seg2 = 5.times.map do |i|
        lon, lat = coord(i + 20)
        make_point(user: user, tracker_id: 'device-rt', time: reference - 2.hours + (i * 5).minutes, lon: lon,
                   lat: lat, altitude: 70)
      end

      points = [p_pre_a, p_pre_b, orphan] + seg1 + seg2
      seed_remap!(:tracks, [preceding.id])
      input = empty_input.merge(users: [dump_user(user)], tracks: [dump_track(preceding)],
                                points: points.map { |p| dump_point(p) })

      calls = [{ service: 'Tracks::IncrementalGenerator', now: reference }]

      known = { preceding.id => track_identity(preceding) }
      events, = capture_track_events(known) do
        perform_enqueued_jobs { Tracks::IncrementalGenerator.new(user).call }
      end

      write_fixture('realtime', { input: input, expected: dump_all_tracks_and_segments(user).merge(
        points: point_track_map(points), events: events
      ), call: calls })
    end
  end

  it 'writes recalculate.json' do
    user = create(:user)
    base = berlin_time(2026, 9, 1, 8, 0)

    c1_points = 3.times.map do |i|
      lon, lat = coord(i)
      make_point(user: user, tracker_id: 'device-c1', time: base + (i * 5).minutes, lon: lon, lat: lat, altitude: 50)
    end
    c1 = build_track!(user: user, tracker_id: 'device-c1', start_at: c1_points.first.recorded_at,
                      end_at: c1_points.last.recorded_at)
    Point.where(id: c1_points.map(&:id)).update_all(track_id: c1.id)
    Tracks::Recalculator.call(c1, broadcast: false)
    extra_lon, extra_lat = coord(3)
    extra = make_point(user: user, tracker_id: 'device-c1', time: base + 20.minutes, lon: extra_lon, lat: extra_lat,
                       altitude: 50, track_id: c1.id)

    c2_points = 3.times.map do |i|
      lon, lat = coord(i + 10)
      make_point(user: user, tracker_id: 'device-c2', time: base + 1.hour + (i * 5).minutes, lon: lon, lat: lat,
                 altitude: 50)
    end
    c2 = build_track!(user: user, tracker_id: 'device-c2', start_at: c2_points.first.recorded_at,
                      end_at: c2_points.last.recorded_at)
    Point.where(id: c2_points.map(&:id)).update_all(track_id: c2.id)
    Tracks::Recalculator.call(c2, broadcast: false)

    c3_lon, c3_lat = coord(20)
    c3_point = make_point(user: user, tracker_id: 'device-c3', time: base + 2.hours, lon: c3_lon, lat: c3_lat,
                          altitude: 50)
    c3 = build_track!(user: user, tracker_id: 'device-c3', start_at: c3_point.recorded_at,
                      end_at: c3_point.recorded_at)
    c3_point.update!(track_id: c3.id)

    points = c1_points + [extra] + c2_points + [c3_point]
    seed_remap!(:tracks, [c1.id, c2.id, c3.id])
    input = empty_input.merge(users: [dump_user(user)], tracks: [c1, c2, c3].map { |t| dump_track(t) },
                              points: points.map { |p| dump_point(p) })

    calls = [c1, c2, c3].map { |t| { service: 'Tracks::RecalculateJob', track_id: remap_id(:tracks, t.id) } }

    known = { c1.id => track_identity(c1), c2.id => track_identity(c2), c3.id => track_identity(c3) }
    events, = capture_track_events(known) do
      Tracks::RecalculateJob.perform_now(c1.id)
      Tracks::RecalculateJob.perform_now(c2.id)
      Tracks::RecalculateJob.perform_now(c3.id)
    end

    write_fixture('recalculate', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events
    ), call: calls })
  end

  it 'writes elevation.json' do
    user = create(:user)
    builder = TracksFixtureBuilder.new(user)
    base = berlin_time(2026, 10, 1, 8, 0)

    l0 = coord(0)
    l1 = coord(1)
    l2 = coord(2)
    l3 = coord(3)
    mixed_points = [
      make_point(user: user, tracker_id: 'device-elev', time: base, lon: l0[0], lat: l0[1], altitude: 100,
                 altitude_decimal: nil),
      make_point(user: user, tracker_id: 'device-elev', time: base + 5.minutes, lon: l1[0], lat: l1[1], altitude: 80,
                 altitude_decimal: 120.7),
      make_point(user: user, tracker_id: 'device-elev', time: base + 10.minutes, lon: l2[0], lat: l2[1], altitude: nil,
                 altitude_decimal: nil),
      make_point(user: user, tracker_id: 'device-elev', time: base + 15.minutes, lon: l3[0], lat: l3[1], altitude: 60,
                 altitude_decimal: 45.2)
    ]
    input = empty_input.merge(users: [dump_user(user)], points: mixed_points.map { |p| dump_point(p) })

    distance = Point.calculate_distance_for_array_geocoder(mixed_points, :m)
    elevation_track = builder.create_track_from_points(mixed_points, distance, tracker_id: 'device-elev',
                                                                                skip_segment_detection: true)
    seed_remap!(:tracks, [elevation_track.id])

    clamp_cases = [150_000_000.4, -42.0, 99_999_999.6, 0].map do |value|
      { input_distance: value, output_distance: builder.send(:clamp_distance, value) }
    end

    avg_speed_cases = [
      [100_000, 60], [0, 60], [100, 0], [10_000_000, 1], [36_000, 3600], [0, 0]
    ].map do |distance_m, duration_s|
      { distance: distance_m, duration: duration_s, avg_speed_kmh: Track.avg_speed_kmh(distance_m, duration_s) }
    end

    calls = [{ service: 'Tracks::TrackBuilder#create_track_from_points', tracker_id: 'device-elev',
               pre_calculated_distance: distance, skip_segment_detection: true }]

    write_fixture('elevation', { input: input, expected: {
                    elevation_track: dump_track(elevation_track), clamp_cases: clamp_cases,
                    avg_speed_cases: avg_speed_cases
                  }, call: calls })
  end

  it 'writes transport_stages.json' do
    user = create(:user)
    base = berlin_time(2026, 11, 1, 8, 0)
    enabled_modes = Track::TRANSPORTATION_MODES.keys

    tracks_data = TracksFixtureOracle::TRANSPORT_TRACK_NAMES.each_with_index.to_h do |name, track_index|
      track_base = base + (track_index * 1.day)
      rows_specs = transport_track_spec(name)
      points = rows_specs.map do |spec|
        make_point(user: user, tracker_id: "device-#{name}", time: track_base + spec[:offset], lon: spec[:lon],
                   lat: spec[:lat], velocity: spec[:velocity], accuracy: spec[:accuracy],
                   motion_data: spec[:motion_data], altitude: 50)
      end
      seed_remap!(:points, points.map(&:id))
      track = build_track!(user: user, tracker_id: "device-#{name}", start_at: points.first.recorded_at,
                           end_at: points.last.recorded_at)
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)

      raw_rows = TransportationModes::FeatureExtractor.call(track.id)
      calibrated_rows = raw_rows.map(&:dup)
      TransportationModes::SpeedCalibrator.call(calibrated_rows)
      preprocessed_rows = TransportationModes::Preprocessor.call(raw_rows.map(&:dup))
      windows = TransportationModes::Windower.call(preprocessed_rows.map(&:dup))
      decoded = TransportationModes::Decoder.call(windows, enabled: enabled_modes)
      segments = TransportationModes::Detector.new(track, enabled_modes: enabled_modes).call

      [name, { points: points, track: track, feature_extractor: remap_point_id_rows(raw_rows),
               speed_calibrator: remap_point_id_rows(calibrated_rows),
               preprocessor: remap_point_id_rows(preprocessed_rows), windower: remap_point_ids_windows(windows),
               decoder: decoded, segments: segments }]
    end

    seed_remap!(:tracks, tracks_data.values.map { |d| d[:track].id })
    all_points = tracks_data.values.flat_map { |d| d[:points] }
    input = empty_input.merge(users: [dump_user(user)], points: all_points.map { |p| dump_point(p) },
                              tracks: tracks_data.values.map { |d| dump_track(d[:track]) })

    expected = tracks_data.to_h do |name, d|
      [name.to_s, { track: dump_track(d[:track]), feature_extractor: d[:feature_extractor],
                    speed_calibrator: d[:speed_calibrator], preprocessor: d[:preprocessor],
                    windower: d[:windower], decoder: d[:decoder], segments: d[:segments] }]
    end

    write_fixture('transport_stages', { input: input, expected: expected, call: [] })
  end

  it 'writes transport_reclassify.json' do
    user = create(:user)
    user.update!(settings: user.settings.merge('enabled_transportation_modes' => %w[walking driving]))
    base = berlin_time(2026, 12, 1, 8, 0)

    rows_specs = build_phases(TracksFixtureOracle::LON, TracksFixtureOracle::LAT, [
                                { count: 4, dt: 30, velocity: '1.3', lon_step: 0.00001, lat_step: 0.00001 },
                                { count: 4, dt: 30, velocity: '20.0', lon_step: 0.0002, lat_step: 0.0001 },
                                { count: 4, dt: 30, velocity: '1.3', lon_step: 0.00001, lat_step: 0.00001 }
                              ])
    points = rows_specs.map do |spec|
      make_point(user: user, tracker_id: 'device-reclassify', time: base + spec[:offset], lon: spec[:lon],
                 lat: spec[:lat], velocity: spec[:velocity], accuracy: 5, motion_data: {}, altitude: 40)
    end
    track = build_track!(user: user, tracker_id: 'device-reclassify', start_at: points.first.recorded_at,
                         end_at: points.last.recorded_at)
    Point.where(id: points.map(&:id)).update_all(track_id: track.id)

    manual = TrackSegment.create!(track: track, transportation_mode: :cycling, corrected_at: base - 1.hour,
                                  start_at: points[4].recorded_at, end_at: points[7].recorded_at, distance: 400,
                                  duration: 90, avg_speed: 16.0, max_speed: 20.0, confidence: :high,
                                  source: 'manual')
    legacy = TrackSegment.create!(track: track, transportation_mode: :running, corrected_at: base - 365.days,
                                  start_index: 0, end_index: 2, distance: 30, duration: 60, avg_speed: 1.8,
                                  max_speed: 2.0, confidence: :medium, source: 'manual')

    seed_remap!(:tracks, [track.id])
    input = empty_input.merge(users: [dump_user(user)], tracks: [dump_track(track)],
                              track_segments: [manual, legacy].map { |s| dump_segment_input(s) },
                              points: points.map { |p| dump_point(p) })

    calls = [{ service: 'TransportationModes::ReclassifyTrackJob', track_id: remap_id(:tracks, track.id) }]

    known = { track.id => track_identity(track) }
    events, = capture_track_events(known) { TransportationModes::ReclassifyTrackJob.perform_now(track.id) }

    tie_segments = [
      TrackSegment.new(transportation_mode: :driving, distance: 5000, duration: 600),
      TrackSegment.new(transportation_mode: :train, distance: 5000, duration: 600)
    ]
    tie_input = tie_segments.map do |s|
      { transportation_mode: TrackSegment.transportation_modes[s.transportation_mode], distance: s.distance,
        duration: s.duration }
    end

    write_fixture('transport_reclassify', { input: input, expected: dump_all_tracks_and_segments(user).merge(
      points: point_track_map(points), events: events,
      dominant_mode_tie: { input: tie_input, output: Track.dominant_modes[Track.pick_dominant_mode(tie_segments)] }
    ), call: calls })
  end

  it 'writes ruby_math.json' do
    pairs = 1000.times.map do |i|
      lat1 = 51.0 + ((i % 37) * 0.001)
      lon1 = 12.0 + ((i % 53) * 0.002)
      lat2 = lat1 + (((i * 7) % 11) * 0.0005) - 0.0025
      lon2 = lon1 + (((i * 13) % 17) * 0.0007) - 0.0056
      { lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2 }
    end
    distances = pairs.map { |p| haversine_distance_m(p[:lat1], p[:lon1], p[:lat2], p[:lon2]) }
    sum = distances.sum

    round5_cases = [
      0.0000005, -0.0000005, 1.000005, 2.675, 1.005, -1.005, 0.1, 0.15, 2.5, -2.5, 0.0, -0.0,
      123.456789, 1.0e-10, 99_999.999995, 999_999_999.9999995
    ].map { |value| { input: value, rounded: value.round(5) } }

    write_fixture('ruby_math', { input: empty_input,
                                 expected: { pairs: pairs, distances: distances, distance_sum: sum,
                                             round5_cases: round5_cases }, call: [] })
  end
end
