# frozen_string_literal: true

# rubocop:disable Rails/Output, Style/FormatStringToken, Naming/MethodParameterName, Style/MultilineBlockChain, Layout/LineLength
# Manual CLI benchmark: console output and terse format strings are the point.

# Vector-tile benchmark against a Cloud-shaped account (default 1M points,
# multi-year, dense home city + trips). NOT run by CI — execute manually:
#
#   DATABASE_NAME=dawarich_mvt_perf RAILS_ENV=test bundle exec rails runner \
#     "require Rails.root.join('lib/perf/vector_tile_benchmark'); Perf::VectorTileBenchmark.new.run"
#
# Seeds once (reuses the account on later runs), then measures warm per-tile
# query time, MVT bytes, and feature count for z ∈ {2, 5, 8, 11, 14} across a
# 3x3 viewport around the dense cluster, with an all-time range. The numbers
# feed the GRID_PX tier tuning in Points::VectorTileQuery.
module Perf
  class VectorTileBenchmark
    TOTAL_POINTS = Integer(ENV.fetch('BENCH_POINTS', 1_000_000))
    # Dense-cluster anchor: Leipzig
    HOME_LAT = 51.3402
    HOME_LON = 12.3712
    ZOOMS = [2, 5, 8, 11, 14].freeze
    YEARS = 3

    TOTAL_TRACKS = Integer(ENV.fetch('BENCH_TRACKS', 3_400))

    def run
      user = seed_user
      puts "Account: #{user.points.count} points"

      rows = ZOOMS.flat_map { |z| measure_viewport(user, z) }
      print_table(rows)
      print_viewport_summary(rows)

      seed_tracks(user)
      puts "\nTracks: #{user.tracks.count}"
      track_rows = ZOOMS.flat_map { |z| measure_tracks_viewport(user, z) }
      print_table(track_rows)
      print_viewport_summary(track_rows)
      measure_simplify_variants(user)
    end

    private

    # Synthetic but dense-shaped tracks: random walks inside the home cluster
    # (plus regional/trip outliers), ~250 vertices each, spread over the same
    # 3 years. The seeded POINTS are uniform noise, so generating tracks from
    # them would produce starbursts — walks are the honest shape for cost.
    def seed_tracks(user)
      existing = user.tracks.count
      return if existing >= TOTAL_TRACKS

      puts "Seeding #{TOTAL_TRACKS - existing} tracks..."
      rng = Random.new(43)
      now = Time.current
      base_ts = (now - YEARS.years).to_i
      span = now.to_i - base_ts

      (existing...TOTAL_TRACKS).each_slice(500) do |slice|
        batch = slice.map do |i|
          roll = rng.rand
          lat = HOME_LAT + (rng.rand - 0.5) * (roll < 0.85 ? 0.12 : 4.0)
          lon = HOME_LON + (rng.rand - 0.5) * (roll < 0.85 ? 0.18 : 6.0)
          coords = Array.new(250) do
            lat += (rng.rand - 0.5) * 0.0015
            lon += (rng.rand - 0.5) * 0.0022
            "#{lon.round(6)} #{lat.round(6)}"
          end
          start_at = Time.zone.at(base_ts + (i.to_f / TOTAL_TRACKS * span).to_i)
          { user_id: user.id, start_at: start_at, end_at: start_at + 2.hours,
            original_path: "LINESTRING(#{coords.join(', ')})",
            distance: 10_000, avg_speed: rng.rand(3.0..120.0).round(2), duration: 7_200,
            tracker_id: "bench-#{i}", created_at: now, updated_at: now }
        end
        # Bench DB only — deliberately skips callbacks and the tile-epoch bump.
        Track.insert_all(batch)
        print "\r#{[slice.last + 1, TOTAL_TRACKS].min}/#{TOTAL_TRACKS}"
      end
      puts
    end

    def measure_tracks_viewport(user, zoom)
      cx, cy = tile_for(HOME_LAT, HOME_LON, zoom)
      max = (1 << zoom) - 1

      [-1, 0, 1].product([-1, 0, 1]).filter_map do |dx, dy|
        measure_track_tile(user, zoom, (cx + dx).clamp(0, max), (cy + dy).clamp(0, max))
      end.uniq { |r| [r[:z], r[:x], r[:y]] }
    end

    def measure_track_tile(user, zoom, x, y)
      query = Tracks::VectorTileQuery.new(scope: user.tracks, z: zoom, x: x, y: y)
      query.call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = query.call
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)

      tile = result.tile.to_s
      tile = [tile.delete_prefix('\x')].pack('H*') if tile.start_with?('\x')
      { z: zoom, x: x, y: y, ms: elapsed_ms, bytes: tile.bytesize,
        features: result.feature_count, timed_out: false }
    rescue ActiveRecord::QueryCanceled
      { z: zoom, x: x, y: y, ms: VectorTileTimeout.query_timeout_ms,
        bytes: 0, features: 0, timed_out: true }
    end

    # The simplify CHOICE, measured — none vs ST_Simplify vs
    # ST_SimplifyPreserveTopology on the densest home tile per zoom tier.
    def measure_simplify_variants(user)
      puts "\nSimplify variants (dense home tile):"
      puts format('%4s %-24s %9s %10s %10s', 'z', 'variant', 'warm ms', 'bytes', 'vertices')
      [2, 5, 8, 11].each do |zoom|
        x, y = tile_for(HOME_LAT, HOME_LON, zoom)
        tolerance = Tracks::VectorTileQuery::WEB_MERCATOR_WORLD / (1 << zoom) / 512
        { 'none' => nil,
          'ST_Simplify' => "ST_Simplify(%s, #{tolerance})",
          'ST_SimplifyPreserveTopology' => "ST_SimplifyPreserveTopology(%s, #{tolerance})" }
          .each do |label, template|
          geom = 'ST_Transform(tracks.original_path, 3857)'
          geom = format(template, geom) if template
          sql = <<~SQL.squish
            WITH features AS (
              SELECT ST_AsMVTGeom(#{geom}, ST_TileEnvelope(#{zoom}, #{x}, #{y}), 4096, 256, true) AS geom
              FROM (#{user.tracks.select(:original_path).to_sql}) AS tracks
              WHERE ST_Intersects(tracks.original_path,
                                  ST_Transform(ST_TileEnvelope(#{zoom}, #{x}, #{y}, margin => 0.0625), 4326))
            )
            SELECT COALESCE(LENGTH(ST_AsMVT(features.*, 'tracks', 4096, 'geom')), 0) AS bytes,
                   COALESCE(SUM(ST_NPoints(geom)), 0) AS vertices
            FROM features WHERE geom IS NOT NULL
          SQL
          ActiveRecord::Base.connection.select_one(sql)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          row = ActiveRecord::Base.connection.select_one(sql)
          ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
          puts format('%4d %-24s %9.1f %10d %10d', zoom, label, ms, row['bytes'].to_i, row['vertices'].to_i)
        end
      end
    end

    def seed_user
      user = User.find_or_create_by!(email: 'tile-bench@example.com') do |u|
        u.password = 'benchmark-password'
      end
      existing = user.points.count
      return user if existing >= TOTAL_POINTS

      seed_points(user, TOTAL_POINTS - existing)
      user
    end

    def seed_points(user, remaining)
      puts "Seeding #{remaining} points..."
      rng = Random.new(42)
      now = Time.current
      base_ts = (now - YEARS.years).to_i
      span = now.to_i - base_ts
      trips = Array.new(12) { [rng.rand(-60.0..60.0), rng.rand(-150.0..150.0)] }

      seeded = 0
      while seeded < remaining
        batch = Array.new([10_000, remaining - seeded].min) do |i|
          roll = rng.rand
          if roll < 0.7 # dense home cluster with commute spread
            lat = HOME_LAT + (rng.rand - 0.5) * 0.12
            lon = HOME_LON + (rng.rand - 0.5) * 0.18
          elsif roll < 0.9 # regional
            lat = HOME_LAT + (rng.rand - 0.5) * 4.0
            lon = HOME_LON + (rng.rand - 0.5) * 6.0
          else # world trips
            trip_lat, trip_lon = trips.sample(random: rng)
            lat = trip_lat + (rng.rand - 0.5) * 0.2
            lon = trip_lon + (rng.rand - 0.5) * 0.2
          end
          { user_id: user.id,
            timestamp: base_ts + ((seeded + i).to_f / remaining * span).to_i + rng.rand(30),
            lonlat: "POINT(#{lon.round(6)} #{lat.round(6)})",
            created_at: now, updated_at: now }
        end
        batch.uniq! { |r| [r[:lonlat], r[:timestamp], r[:user_id]] }
        Point.insert_all(batch, unique_by: %i[user_id timestamp lonlat])
        seeded += batch.size
        print "\r#{seeded}/#{remaining}"
      end
      puts
    end

    def tile_for(lat, lon, zoom)
      n = 1 << zoom
      x = ((lon + 180.0) / 360.0 * n).floor.clamp(0, n - 1)
      lat_rad = lat * Math::PI / 180.0
      y = ((1.0 - Math.log(Math.tan(lat_rad) + (1 / Math.cos(lat_rad))) / Math::PI) / 2.0 * n)
          .floor.clamp(0, n - 1)
      [x, y]
    end

    def measure_viewport(user, zoom)
      cx, cy = tile_for(HOME_LAT, HOME_LON, zoom)
      max = (1 << zoom) - 1

      offsets = [-1, 0, 1].product([-1, 0, 1])
      offsets.filter_map do |dx, dy|
        x = (cx + dx).clamp(0, max)
        y = (cy + dy).clamp(0, max)
        measure_tile(user, zoom, x, y)
      end.uniq { |r| [r[:z], r[:x], r[:y]] }
    end

    def measure_tile(user, zoom, x, y)
      query = Points::VectorTileQuery.new(scope: user.points, z: zoom, x: x, y: y)
      query.call # cold run warms caches
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = query.call
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)

      tile = result.tile.to_s
      tile = [tile.delete_prefix('\x')].pack('H*') if tile.start_with?('\x')
      { z: zoom, x: x, y: y, ms: elapsed_ms, bytes: tile.bytesize,
        features: result.feature_count, timed_out: false }
    rescue ActiveRecord::QueryCanceled
      { z: zoom, x: x, y: y, ms: VectorTileTimeout.query_timeout_ms,
        bytes: 0, features: 0, timed_out: true }
    end

    def print_table(rows)
      puts format('%4s %6s %6s %9s %10s %9s %s', 'z', 'x', 'y', 'warm ms', 'bytes', 'features', 'timeout')
      rows.each do |r|
        puts format('%4d %6d %6d %9.1f %10d %9d %s',
                    r[:z], r[:x], r[:y], r[:ms], r[:bytes], r[:features], r[:timed_out] ? 'TIMEOUT' : '')
      end
    end

    def print_viewport_summary(rows)
      puts "\nPer-viewport (9-tile) summary:"
      rows.group_by { |r| r[:z] }.each do |zoom, tile_rows|
        puts format('z=%-2d tiles=%d total_ms=%.1f total_bytes=%d total_features=%d worst_ms=%.1f worst_bytes=%d timeouts=%d',
                    zoom, tile_rows.size,
                    tile_rows.sum { |r| r[:ms] },
                    tile_rows.sum { |r| r[:bytes] },
                    tile_rows.sum { |r| r[:features] },
                    tile_rows.map { |r| r[:ms] }.max,
                    tile_rows.map { |r| r[:bytes] }.max,
                    tile_rows.count { |r| r[:timed_out] })
      end
    end
  end
end
# rubocop:enable Rails/Output, Style/FormatStringToken, Naming/MethodParameterName, Style/MultilineBlockChain, Layout/LineLength
