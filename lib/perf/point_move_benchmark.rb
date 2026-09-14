# frozen_string_literal: true

# Run with:
#   RAILS_ENV=test bundle exec rails runner lib/perf/point_move_benchmark.rb
# Optional:
#   POINT_MOVE_SIZES=100,1000 POINT_MOVE_RUNS=5 \
#     POINT_MOVE_VARIANTS=legacy,optimized bundle exec rails runner ...
# rubocop:disable Rails/Output -- this CLI emits machine-readable benchmark results.

class PointMoveBenchmark
  DEFAULT_SIZES = [100, 1_000, 10_000, 50_000].freeze
  DEFAULT_VARIANTS = %w[legacy optimized].freeze
  SEGMENT_COUNT = 10

  def initialize
    @sizes = integer_list('POINT_MOVE_SIZES', DEFAULT_SIZES)
    @runs = Integer(ENV.fetch('POINT_MOVE_RUNS', 5))
    @variants = ENV.fetch('POINT_MOVE_VARIANTS', DEFAULT_VARIANTS.join(',')).split(',')
    unknown_variants = variants - DEFAULT_VARIANTS
    raise ArgumentError, "Unknown variants: #{unknown_variants.join(', ')}" if unknown_variants.any?
    raise ArgumentError, 'POINT_MOVE_RUNS must be positive' unless runs.positive?

    @owned_user = ENV['POINT_MOVE_USER_ID'].blank?
    @user = if @owned_user
              User.create!(
                email: "point-move-benchmark-#{SecureRandom.hex(8)}@example.invalid",
                password: SecureRandom.hex(16), status: :active, active_until: 1.year.from_now
              )
            else
              User.find(Integer(ENV.fetch('POINT_MOVE_USER_ID')))
            end
  end

  def call
    Rails.logger.level = Logger::WARN
    emit(event: 'point_move.benchmark_started', sizes: sizes, runs: runs, variants: variants)
    sizes.each do |size|
      variants.each { |variant| benchmark(size, variant) }
    end
  ensure
    user.destroy! if @owned_user && user&.persisted?
  end

  private

  attr_reader :sizes, :runs, :variants, :user

  def integer_list(name, default)
    ENV.fetch(name, default.join(',')).split(',').map { |value| Integer(value) }
  end

  def benchmark(size, variant)
    track = create_track(size)
    create_points(track, size)
    create_segments(track, size)
    point = track.points.order(:timestamp, :id).offset(size / 2).first
    samples = Array.new(runs) { |run| measure_run(track, point, size, variant, run + 1) }
    emit_summary(size, variant, samples)
  ensure
    Point.where(track_id: track&.id).delete_all
    track&.reload&.destroy!
  end

  def measure_run(track, point, size, variant, run)
    notification_payload = nil
    notification_subscriber = ActiveSupport::Notifications.subscribe('point_move.map') do |event|
      notification_payload = event.payload
    end
    query_count = 0
    sql_subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
      query_count += 1 unless %w[SCHEMA TRANSACTION CACHE].include?(event.payload[:name])
    end
    allocations_before = GC.stat(:total_allocated_objects)
    status = 'success'
    error_class = nil

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      perform_move(variant, track, point, run)
    rescue StandardError => e
      status = 'failed'
      error_class = e.class.name
    ensure
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      ActiveSupport::Notifications.unsubscribe(notification_subscriber)
      ActiveSupport::Notifications.unsubscribe(sql_subscriber)
    end

    sample = {
      event: 'point_move.benchmark', variant: variant, run: run,
      status: status, error_class: error_class, point_count: size,
      segment_count: track.track_segments.count,
      duration_ms: (elapsed.to_f * 1_000).round(2), query_count: query_count,
      allocations: GC.stat(:total_allocated_objects) - allocations_before,
      geometry_bytes: geometry_bytes(track),
      lock_wait_ms: ((notification_payload&.fetch(:lock_wait, 0) || 0) * 1_000).round(2)
    }
    emit(sample)
    sample
  end

  # Reconstructs the pre-change Point update plus asynchronous job's legacy
  # calculation in-process so the full old operation can be measured. This is
  # intentionally not feature-equivalent: it neither recalculates segments nor
  # returns a canonical Track to the caller.
  def perform_move(variant, track, point, run)
    direction = run.odd? ? 1 : -1
    point.reload
    next_longitude = point.lon + (direction * 0.0001)
    next_latitude = point.lat + (direction * 0.0001)

    if variant == 'legacy'
      point.update!(lonlat: "POINT(#{next_longitude} #{next_latitude})")
      track.reload.recalculate_path_and_distance!
      return
    end

    track.reload
    Points::Move.call(
      user: user,
      point_id: point.id,
      latitude: next_latitude,
      longitude: next_longitude,
      point_revision: point.lock_version,
      track_revision: track.lock_version,
      history_scope: { start_at: track.start_at.to_i, end_at: track.end_at.to_i }
    )
  end

  def emit_summary(size, variant, samples)
    successful = samples.select { |sample| sample[:status] == 'success' }
    durations = successful.pluck(:duration_ms).sort
    emit(
      event: 'point_move.benchmark_summary', variant: variant, point_count: size,
      runs: samples.size, successful_runs: successful.size,
      median_duration_ms: percentile(durations, 0.5), p95_duration_ms: percentile(durations, 0.95),
      max_duration_ms: durations.max, median_queries: percentile(successful.pluck(:query_count).sort, 0.5),
      median_allocations: percentile(successful.pluck(:allocations).sort, 0.5),
      geometry_bytes: successful.last&.fetch(:geometry_bytes, nil),
      max_lock_wait_ms: successful.pluck(:lock_wait_ms).max
    )
  end

  def percentile(values, quantile)
    return nil if values.empty?

    values[[(values.length * quantile).ceil - 1, 0].max]
  end

  def create_track(size)
    started_at = Time.zone.at(1_700_000_000 - size)
    Track.create!(
      user: user, start_at: started_at, end_at: started_at + size.seconds,
      original_path: 'LINESTRING(13.4 52.5, 13.5 52.6)', distance: 1, avg_speed: 1, duration: size
    )
  end

  def create_points(track, size)
    now = Time.current
    base_timestamp = track.start_at.to_i
    rows = Array.new(size) do |index|
      longitude = 13.4 + ((index % 10_000) * 0.000001)
      latitude = 52.5 + ((index / 10_000) * 0.000001)
      {
        user_id: user.id, track_id: track.id, timestamp: base_timestamp + index,
        lonlat: "POINT(#{longitude} #{latitude})", geodata: {}, motion_data: {}, raw_data: {},
        raw_data_archived: false, in_regions: [], inrids: [], lock_version: 0,
        created_at: now, updated_at: now
      }
    end
    rows.each_slice(5_000) { |batch| Point.insert_all!(batch) }
  end

  def create_segments(track, size)
    segment_size = (size.to_f / SEGMENT_COUNT).ceil
    (0...size).each_slice(segment_size).with_index do |indexes, index|
      TrackSegment.create!(
        track: track, start_index: indexes.first, end_index: indexes.last,
        transportation_mode: index.even? ? :walking : :driving,
        confidence: :medium, source: 'benchmark', distance: 0, duration: indexes.size
      )
    end
  end

  def geometry_bytes(track)
    Track.where(id: track.id).pick(Arel.sql('ST_MemSize(original_path)')).to_i
  end

  def emit(payload)
    $stdout.write("#{JSON.generate(payload)}\n")
  end
end

PointMoveBenchmark.new.call
# rubocop:enable Rails/Output
