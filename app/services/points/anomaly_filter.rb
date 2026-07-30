# frozen_string_literal: true

class Points::AnomalyFilter
  MAX_SPEED_KMH = 1000 # km/h — floor for speed threshold
  SPEED_MULTIPLIER = 3 # threshold = max(floor, median * multiplier)
  CONTEXT_POINTS = 5   # extra points for speed context at boundaries
  # Two points sharing a timestamp have no meaningful speed, but a displacement
  # this large between them is still an instantaneous jump. Treating it as
  # "unknown" let outliers through: a point whose neighbour shared its timestamp
  # was skipped outright, however impossible its own position was.
  TELEPORT_METERS = 1_000
  # Longest run of consecutive points that may be convicted as one displaced
  # reading. Bad GPS arrives as a brief excursion — one point, occasionally a
  # handful. A genuine stay bracketed by two impossible hops (sparse sampling
  # either side of a real trip, or a second device interleaved) is far longer,
  # and flagging it wholesale would erase real history. Under-flagging a long
  # noise burst is the safer failure.
  MAX_DISPLACED_RUN_POINTS = 5
  # Accuracy radius beyond which a reading carries no usable position at all.
  # Deliberately far above any plausible GPS/wifi/cell error: a reported radius
  # is a confidence estimate, not proof the position is wrong. Google Timeline
  # routinely reports 1-4km for points that sit exactly on the road, and
  # deleting those replaced real route geometry with straight lines across the
  # gap — strictly worse than keeping a point that may be a couple of km off.
  # Positions that are genuinely wrong are caught by the speed passes instead.
  ABSURD_ACCURACY_METERS = 10_000
  # Ceiling for the EXTRA distance an excursion adds, which is a different
  # question from how fast a single leg was. A genuine journey adds nothing —
  # its displacement is the trip — so any excess at all is travel that did not
  # happen, and demanding 1000 km/h of it before acting is far too lax. Google
  # splices stale fixes from other devices into a phone's timelinePath, and each
  # leg then reads as ordinary air travel while the round trip needs hundreds of
  # extra km/h. Well above any road or rail speed, well below a plausible flight.
  MAX_DETOUR_SPEED_KMH = 300
  # A stale fix can sit hours from its neighbours, where the round trip it
  # implies is slow enough to be physically possible and no speed test can
  # condemn it. What condemns it is the shape: the fixes either side are the
  # same stay, the excursion is far from it, and nothing was spent being there.
  # Real travel away from a stay leaves hours of readings at the far end.
  STAY_RADIUS_METERS = 25_000        # how close two fixes must be to be one stay
  MIN_EXCURSION_METERS = 50_000      # how far the excursion must depart from it
  MAX_EXCURSION_SPAN_SECONDS = 1_800 # dwell above this is a visit, not a stray fix

  def initialize(user_id, start_time, end_time)
    @user_id = user_id
    @start_time = start_time
    @end_time = end_time
  end

  def call
    return 0 unless filtering_enabled?

    count = 0
    count += filter_null_island
    count += filter_by_accuracy
    count += filter_by_speed
    count
  end

  private

  def user_settings
    @user_settings ||= User.find(@user_id).safe_settings
  end

  def filtering_enabled?
    user_settings.gps_filtering_enabled?
  end

  # Pass 0: Null Island — a sustained (0,0) run defeats the speed sandwich
  # (internal speeds are 0), so exact zeros are flagged unconditionally.
  def filter_null_island
    Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
         .not_anomaly
         .null_island
         .update_all(anomaly: true, updated_at: Time.current)
  end

  # Pass 1: Mark points whose reported accuracy radius is so large the reading
  # cannot be a position at all. See ABSURD_ACCURACY_METERS for why this is not
  # the user's gps_accuracy_threshold.
  def filter_by_accuracy
    Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
         .not_anomaly
         .where.not(accuracy: nil)
         .where('accuracy > ?', ABSURD_ACCURACY_METERS)
         .update_all(anomaly: true, updated_at: Time.current)
  end

  # Pass 2: Speed-based sandwich test (chunked by month to handle large imports)
  def filter_by_speed
    count = 0

    each_monthly_chunk do |chunk_start, chunk_end|
      count += filter_speed_chunk(chunk_start, chunk_end)
    end

    count
  end

  def each_monthly_chunk
    chunk_start = @start_time

    while chunk_start <= @end_time
      month_end = Time.zone.at(chunk_start).end_of_month.to_i
      chunk_end = [month_end, @end_time].min
      yield chunk_start, chunk_end
      chunk_start = chunk_end + 1
    end
  end

  def filter_speed_chunk(chunk_start, chunk_end)
    points, main_points = fetch_points_with_context(chunk_start, chunk_end)
    return 0 if points.size < 3

    speeds_by_point = calculate_all_speeds(points.map(&:id))
    return 0 if speeds_by_point.empty?

    threshold = speed_threshold(speeds_by_point)
    return 0 if threshold.nil?

    # Only check points in the main range (not context points)
    main_range_ids = main_points.map(&:id).to_set

    # Each device is its own stream. Interleaving them by timestamp invents
    # journeys between devices that nobody made — the same reason track
    # generation groups by tracker_id (Tracks::TimeChunkProcessorJob).
    anomaly_ids = points.group_by { |point| point.tracker_id.to_s }.values.flat_map do |stream|
      displaced_run_ids(stream, speeds_by_point, threshold, main_range_ids)
    end

    return 0 if anomaly_ids.empty?

    Point.where(id: anomaly_ids).update_all(anomaly: true, updated_at: Time.current)
  end

  def speed_threshold(speeds_by_point)
    all_speeds = speeds_by_point.values.flat_map { |h| [h[:incoming], h[:outgoing]] }.compact
    return nil if all_speeds.empty?

    floor_mps = MAX_SPEED_KMH / 3.6
    # Compute median from non-extreme speeds only so outliers don't inflate the threshold
    normal_speeds = all_speeds.select { |s| s <= floor_mps }
    median = normal_speeds.empty? ? 0.0 : median_speed(normal_speeds)
    [floor_mps, median * SPEED_MULTIPLIER].max
  end

  # A displaced GPS reading is often several consecutive points, not one spike,
  # and its return leg is often slow enough to look like an ordinary flight.
  # Each candidate excursion is therefore judged on the distance it ADDS versus
  # going straight from the fix before it to the fix after it.
  def displaced_run_ids(stream, speeds_by_point, threshold, main_range_ids)
    displaced = Set.new

    # Slide a window of every allowed run length over the stream, judging each
    # against the fixes immediately either side of it. Splitting the stream into
    # runs first cannot isolate an excursion whose return leg looks plausible —
    # the excursion simply absorbs the points that follow it.
    # Shortest windows first: once an excursion is explained, longer windows that
    # merely wrap it in innocent neighbours must not convict those neighbours too.
    (1..MAX_DISPLACED_RUN_POINTS).each do |length|
      stream.each_cons(length + 2) do |window|
        previous_point = window.first
        next_point = window.last
        run = window[1..-2]

        next if run.any? { |point| displaced.include?(point.id) }
        next unless suspicious_boundary?(run, speeds_by_point, threshold)
        unless both_legs_impossible?(run, speeds_by_point, threshold) ||
               detour_speed(run, previous_point, next_point) > detour_ceiling ||
               contradicts_stay?(run, previous_point, next_point)
          next
        end

        run.each { |point| displaced << point.id if main_range_ids.include?(point.id) }
      end
    end

    displaced.to_a
  end

  # Impossible on both sides convicts on its own: nothing legitimate arrives and
  # departs faster than any aircraft. This catches excursions with no detour to
  # measure — a straight-line hop where the timestamps themselves are wrong.
  def both_legs_impossible?(run, speeds_by_point, threshold)
    entry_speed = speeds_by_point.dig(run.first.id, :incoming)
    exit_speed  = speeds_by_point.dig(run.last.id, :outgoing)
    return false if entry_speed.nil? || exit_speed.nil?

    entry_speed > threshold && exit_speed > threshold
  end

  def detour_ceiling = MAX_DETOUR_SPEED_KMH / 3.6

  # True when the fixes either side belong to one stay and the run leaps away
  # from it without spending any time there. See STAY_RADIUS_METERS.
  def contradicts_stay?(run, previous_point, next_point)
    return false if haversine_meters(previous_point, next_point) > STAY_RADIUS_METERS

    dwell = run.last.timestamp - run.first.timestamp
    return false if dwell > MAX_EXCURSION_SPAN_SECONDS

    haversine_meters(previous_point, run.first) > MIN_EXCURSION_METERS &&
      haversine_meters(run.last, next_point) > MIN_EXCURSION_METERS
  end

  # An excursion has to arrive or leave faster than any ground travel to be worth
  # judging; this keeps the distance maths off the overwhelming majority of
  # ordinary points. The gate is the detour ceiling rather than the raw speed
  # floor, because a stale fix hours from its neighbours has one perfectly
  # ordinary-looking leg and would never clear 1000 km/h on both.
  def suspicious_boundary?(run, speeds_by_point, threshold)
    gate = [threshold, detour_ceiling].min
    entry_speed = speeds_by_point.dig(run.first.id, :incoming)
    exit_speed  = speeds_by_point.dig(run.last.id, :outgoing)

    (entry_speed && entry_speed > gate) || (exit_speed && exit_speed > gate)
  end

  # Extra distance the excursion adds over travelling straight from the previous
  # fix to the next one, spread across the time actually available.
  #
  # A one-way journey adds nothing — the displacement IS the trip, so a real
  # flight scores zero here no matter how fast it was. A stale or mislocated fix
  # jumps away and comes back, adding roughly twice its displacement, which no
  # real travel can cover in the gap. This is what catches excursions whose
  # return leg is slow enough to look plane-like, where requiring both legs to
  # be impossible finds nothing.
  def detour_speed(run, previous_point, next_point)
    seconds = next_point.timestamp - previous_point.timestamp
    return 0.0 unless seconds.positive?

    via_run = haversine_meters(previous_point, run.first) + haversine_meters(run.last, next_point)
    direct  = haversine_meters(previous_point, next_point)

    [via_run - direct, 0.0].max / seconds
  end

  EARTH_RADIUS_METERS = 6_371_008.8

  def haversine_meters(from, to)
    from_lat = to_radians(from.lonlat.y)
    to_lat   = to_radians(to.lonlat.y)
    delta_lat = to_lat - from_lat
    delta_lon = to_radians(to.lonlat.x - from.lonlat.x)

    a = (Math.sin(delta_lat / 2)**2) +
        (Math.cos(from_lat) * Math.cos(to_lat) * (Math.sin(delta_lon / 2)**2))

    2 * EARTH_RADIUS_METERS * Math.asin([1.0, Math.sqrt(a)].min)
  end

  def to_radians(degrees) = degrees * Math::PI / 180

  def fetch_points_with_context(start_time, end_time)
    before_ctx = Point.where(user_id: @user_id).not_anomaly
                      .where('timestamp < ?', start_time)
                      .order(timestamp: :desc).limit(CONTEXT_POINTS)
                      .select(:id, :timestamp, :tracker_id, :lonlat).to_a.reverse

    main = Point.where(user_id: @user_id, timestamp: start_time..end_time)
                .not_anomaly.order(:timestamp)
                .select(:id, :timestamp, :tracker_id, :lonlat).to_a

    after_ctx = Point.where(user_id: @user_id).not_anomaly
                     .where('timestamp > ?', end_time)
                     .order(:timestamp).limit(CONTEXT_POINTS)
                     .select(:id, :timestamp, :tracker_id, :lonlat).to_a

    [before_ctx + main + after_ctx, main]
  end

  # Single CTE query: compute distance and time diff for ALL consecutive pairs
  def calculate_all_speeds(point_ids)
    return {} if point_ids.empty?

    ids_literal = point_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(',')

    sql = <<~SQL
      WITH ordered_points AS (
        SELECT id, lonlat, timestamp,
               LAG(id)        OVER per_device AS prev_id,
               LAG(lonlat)    OVER per_device AS prev_lonlat,
               LAG(timestamp) OVER per_device AS prev_timestamp
        FROM points
        WHERE id = ANY(ARRAY[#{ids_literal}])
        WINDOW per_device AS (PARTITION BY COALESCE(tracker_id, '') ORDER BY timestamp, id)
      )
      SELECT id, prev_id,
             ST_Distance(lonlat::geography, prev_lonlat::geography) AS meters,
             (timestamp - prev_timestamp) AS seconds
      FROM ordered_points
      WHERE prev_id IS NOT NULL
    SQL

    result = {}
    Point.connection.execute(sql).each do |row|
      speed = speed_from(row['meters']&.to_f, row['seconds']&.to_i)
      prev_id = row['prev_id'].to_i
      curr_id = row['id'].to_i

      result[prev_id] ||= {}
      result[prev_id][:outgoing] = speed

      result[curr_id] ||= {}
      result[curr_id][:incoming] = speed
    end
    result
  end

  # Zero elapsed time is only unknowable if the two readings agree on position.
  # A kilometre or more apart in the same second is a jump, not a mystery.
  def speed_from(meters, seconds)
    return nil if meters.nil? || seconds.nil?
    return meters / seconds if seconds.positive?

    meters > TELEPORT_METERS ? Float::INFINITY : nil
  end

  def median_speed(speeds)
    sorted = speeds.compact.sort
    return 0.0 if sorted.empty?

    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
