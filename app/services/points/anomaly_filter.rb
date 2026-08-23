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
  FROZEN_FIX_EXTENT_METERS = 1
  MAX_FROZEN_FIX_SPAN_SECONDS = 3_600
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
  # Radius above which a fix whose motion fields are all CoreLocation
  # sentinels (speed -1, vertical accuracy -1) is treated as a tower position
  # rather than a reading of the user. Wifi trilateration also reports the
  # sentinel combination but lands at 150-450 m and is positionally usable —
  # a stationary indoor point sits where it says. Cell positioning starts
  # around half a kilometre and lands wherever the tower is. The gate sits
  # between the two tiers so only the tower tier is judged at all.
  SENTINEL_ACCURACY_METERS = 500
  # What counts as the precise fix a sentinel one is judged against — a
  # radius any GPS or wifi lock beats, and no tower position reaches.
  PRECISE_FIX_METERS = 100
  # A sentinel fix is only judged against tracking that could have done
  # better: it is flagged when a precise fix sits within this many seconds of
  # it, and kept otherwise. Reduced-accuracy permission, significant-change
  # tracking and genuinely off-grid stretches produce nothing but coarse
  # fixes — there the tower position is the only record there is, and erasing
  # the history it forms is worse than showing its precision honestly. Six
  # hours spans any GPS dropout inside a tracked day without reaching into a
  # neighbouring coarse-only era.
  SENTINEL_PRECISE_NEIGHBOR_SECONDS = 6 * 60 * 60
  # Where a visit report keeps its departure date. motion_data first: raw_data
  # is emptied by archival, and a flag that cannot be re-derived would silently
  # return on the next reset re-run. Both values are untrusted client strings,
  # so the passes prefix-test them instead of casting — a timestamptz cast
  # raises on junk and would fail the whole batch.
  DEPARTURE_DATE_SQL = "COALESCE(motion_data->>'departure_date', " \
                       "raw_data->'properties'->>'departure_date')"

  # invalidate_dependents: flagging detaches points from their tracks and
  # queues the track and the month's stats for a rebuild. The backfill path
  # opts out — it rebuilds every track and stat wholesale after the filter
  # finishes, and per-point enqueues there would only duplicate that work.
  # job_queue moves the dependent rebuilds off their home queues; housekeeping
  # callers pass :low_priority so their per-track recalculations never compete
  # with realtime generation on :tracks.
  def initialize(user_id, start_time, end_time, invalidate_dependents: true, job_queue: nil)
    @user_id = user_id
    @start_time = start_time
    @end_time = end_time
    @invalidate_dependents = invalidate_dependents
    @job_queue = job_queue
  end

  def call
    return 0 unless filtering_enabled?

    @flagged_for_rebuild = []
    count = 0
    count += filter_null_island
    count += filter_by_accuracy
    count += filter_visit_reports
    count += filter_sentinel_fixes
    count += filter_by_speed
    # Anomalies are excluded from vector tiles, so flipping the flag changes
    # tile content without a point write. Bump only the window's years — this
    # runs on every live-ingest batch, so a sentinel here would wipe the whole
    # account's tile cache on the hottest path.
    # Driven by what was actually flagged, not by the caller's window: the
    # sentinel pass reaches back before @start_time, so a run just after New
    # Year touches the previous year's tiles, which would otherwise 304
    # forever. Reading the flagged rows keeps this exact even if another pass
    # grows a lookback of its own. One timestamp per year is all the epoch needs.
    bump_tile_epoch if @flagged_for_rebuild.any?
    enqueue_dependent_rebuilds if @invalidate_dependents && @flagged_for_rebuild.any?
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
    flag_anomalies(
      Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
           .not_anomaly
           .null_island
    )
  end

  # Pass 1: Mark points whose reported accuracy radius is so large the reading
  # cannot be a position at all. See ABSURD_ACCURACY_METERS for why this is not
  # the user's gps_accuracy_threshold.
  def filter_by_accuracy
    flag_anomalies(
      Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
           .not_anomaly
           .where.not(accuracy: nil)
           .where('accuracy > ?', ABSURD_ACCURACY_METERS)
    )
  end

  # Visit-report pass: iOS visit monitoring (Overland `action: visit`) delivers
  # a stay summary AFTER the stay ended — the visit centroid plus arrival and
  # departure dates, stamped with delivery time. The device is already moving
  # away by then, so the track leaps to the centroid and back. The coordinate
  # is right and its radius often single-digit metres; only the timeline
  # placement is wrong, which no accuracy or speed gate can see. An arrival
  # report (no departure date yet) is delivered in place and stays useful —
  # CLVisit marks "not departed" with a distant-future placeholder (year
  # 4001), so the year guard treats any far-future date the same as none. A
  # report whose departure date is unrecoverable (raw payload archived before
  # motion_data kept a copy) cannot be classified and is left alone —
  # under-flagging is the safer failure.
  def filter_visit_reports
    # The departure date is copied into motion_data as part of the flagging
    # UPDATE: raw_data archival would otherwise strip the only evidence, and a
    # later reset re-run would silently unflag the point and bring the leap
    # back.
    relation = Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
                    .not_anomaly
                    .where("motion_data->>'action' = 'visit'")
                    .where("#{DEPARTURE_DATE_SQL} ~ '^\\d{4}-'")
                    .where("#{DEPARTURE_DATE_SQL} < '3000-'")

    flag_anomalies(
      relation,
      "motion_data = motion_data || jsonb_build_object('departure_date', #{DEPARTURE_DATE_SQL})"
    )
  end

  # Sentinel pass: a fix whose motion fields are all invalid markers (speed
  # -1, vertical accuracy -1) with a coarse radius did not come from GPS at
  # all — it is a tower or cell-grid position, delivered wherever coverage
  # begins, and each one drags the track sideways by its full radius, so a
  # burst inside an otherwise-tracked day is flagged whole. The precise-fix
  # neighbour test keeps the pass away from histories that are coarse all the
  # way through: reduced-accuracy permission, significant-change tracking and
  # off-grid stretches produce nothing better, and there the tower position
  # is the only record there is. The neighbour must come from the same device
  # — a second tracker on reduced-accuracy permission stays coarse even when
  # the account's other device is precise, the same per-stream rule the speed
  # pass applies. Imported histories are untouched because their points do
  # not carry the sentinel combination.
  def filter_sentinel_fixes
    # The candidate window reaches back past the caller's range: a wake-up
    # tower fix often arrives in a batch of one, before the precise fixes
    # that condemn it exist, and the batch that brings those fixes starts
    # after it. Each run therefore re-judges the recent past.
    relation = Point.where(user_id: @user_id,
                           timestamp: (@start_time - SENTINEL_PRECISE_NEIGHBOR_SECONDS)..@end_time)
                    .not_anomaly
                    .where(vertical_accuracy: ...0)
                    .where("velocity LIKE '-%'")
                    .where('accuracy > ?', SENTINEL_ACCURACY_METERS)
                    .where(
                      'EXISTS (SELECT 1 FROM points precise ' \
                      'WHERE precise.user_id = points.user_id ' \
                      'AND precise.tracker_id IS NOT DISTINCT FROM points.tracker_id ' \
                      'AND precise.timestamp BETWEEN points.timestamp - :window AND points.timestamp + :window ' \
                      'AND precise.accuracy <= :radius ' \
                      'AND precise.anomaly IS NOT TRUE ' \
                      'AND precise.id <> points.id)',
                      window: SENTINEL_PRECISE_NEIGHBOR_SECONDS, radius: PRECISE_FIX_METERS
                    )

    flag_anomalies(relation)
  end

  # A flagged point leaves its track in the same UPDATE: recalculation reads
  # track.points, so a stale track_id would keep feeding the leap back into
  # the geometry it exists to fix. The rows are collected across passes and
  # their tracks and months rebuilt once, at the end of the run.
  def flag_anomalies(relation, extra_set = nil)
    flagged = relation.pluck(:id, :track_id, :timestamp)
    return 0 if flagged.empty?

    set_clause = 'anomaly = TRUE, track_id = NULL, updated_at = NOW()'
    set_clause = "#{set_clause}, #{extra_set}" if extra_set
    Point.where(id: flagged.map(&:first)).update_all(set_clause)

    @flagged_for_rebuild.concat(flagged)

    flagged.size
  end

  def bump_tile_epoch
    timestamps = @flagged_for_rebuild.each_with_object({}) do |(_id, _track_id, timestamp), per_year|
      per_year[Points::TileEpoch.year_for(timestamp)] ||= timestamp
    end

    Points::TileEpoch.bump(@user_id, timestamps: timestamps.values)
  end

  def enqueue_dependent_rebuilds
    track_jobs = @flagged_for_rebuild.filter_map { |_, track_id, _| track_id }.uniq
                                     .map { |track_id| Tracks::RecalculateJob.new(track_id) }
    stats_jobs = @flagged_for_rebuild.map { |_, _, timestamp| Time.zone.at(timestamp) }
                                     .map { |time| [time.year, time.month] }.uniq
                                     .map { |year, month| Stats::CalculatingJob.new(@user_id, year, month) }

    jobs = track_jobs + stats_jobs
    jobs.each { |job| job.queue_name = @job_queue.to_s } if @job_queue
    ActiveJob.perform_all_later(jobs)
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
      displaced_run_ids(stream, speeds_by_point, threshold, main_range_ids) +
        frozen_fix_run_ids(stream, speeds_by_point, threshold, main_range_ids)
    end

    return 0 if anomaly_ids.empty?

    flag_anomalies(Point.where(id: anomaly_ids))
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

  def frozen_fix_run_ids(stream, speeds_by_point, threshold, main_range_ids)
    frozen = []

    each_frozen_run(stream) do |run|
      next unless both_legs_impossible?(run, speeds_by_point, threshold)

      run.each { |point| frozen << point.id if main_range_ids.include?(point.id) }
    end

    frozen
  end

  def each_frozen_run(stream)
    index = 1
    last = stream.length - 1

    while index < last
      start = index
      index += 1
      index += 1 while index < last && frozen_with?(stream[start], stream[index])

      run = stream[start...index]
      next unless run.length > MAX_DISPLACED_RUN_POINTS
      next if run.last.timestamp - run.first.timestamp > MAX_FROZEN_FIX_SPAN_SECONDS

      yield(run)
    end
  end

  def frozen_with?(anchor, point)
    distance_meters(anchor, point) <= FROZEN_FIX_EXTENT_METERS
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
    return false if distance_meters(previous_point, next_point) > STAY_RADIUS_METERS

    dwell = run.last.timestamp - run.first.timestamp
    return false if dwell > MAX_EXCURSION_SPAN_SECONDS

    distance_meters(previous_point, run.first) > MIN_EXCURSION_METERS &&
      distance_meters(run.last, next_point) > MIN_EXCURSION_METERS
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

    via_run = distance_meters(previous_point, run.first) + distance_meters(run.last, next_point)
    direct  = distance_meters(previous_point, next_point)

    [via_run - direct, 0.0].max / seconds
  end

  def distance_meters(from, to)
    kilometers = Geocoder::Calculations.distance_between(
      [from.lonlat.y, from.lonlat.x], [to.lonlat.y, to.lonlat.x], units: :km
    )

    kilometers * 1_000
  end

  def fetch_points_with_context(start_time, end_time)
    # Tie order must match the per-device window in calculate_all_speeds
    # (ORDER BY timestamp, id), or points sharing a timestamp get speeds
    # attached to the wrong neighbour.
    before_ctx = Point.where(user_id: @user_id).not_anomaly
                      .where('timestamp < ?', start_time)
                      .order(timestamp: :desc, id: :desc).limit(CONTEXT_POINTS)
                      .select(:id, :timestamp, :tracker_id, :lonlat).to_a.reverse

    main = Point.where(user_id: @user_id, timestamp: start_time..end_time)
                .not_anomaly.order(:timestamp, :id)
                .select(:id, :timestamp, :tracker_id, :lonlat).to_a

    after_ctx = Point.where(user_id: @user_id).not_anomaly
                     .where('timestamp > ?', end_time)
                     .order(:timestamp, :id).limit(CONTEXT_POINTS)
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
