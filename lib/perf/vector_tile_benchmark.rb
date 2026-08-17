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

    def run
      user = seed_user
      puts "Account: #{user.points.count} points"

      rows = ZOOMS.flat_map { |z| measure_viewport(user, z) }
      print_table(rows)
      print_viewport_summary(rows)
    end

    private

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
      { z: zoom, x: x, y: y, ms: Points::VectorTileQuery::QUERY_TIMEOUT_MS,
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
