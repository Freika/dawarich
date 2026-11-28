# frozen_string_literal: true

# Finds long stationary stops in the time-ordered samples of one tracker.
#
# A sample is settled when it, every sample in the preceding threshold window and the
# last sample before that window all lie within the radius of it. That last sample
# must be at most one more threshold older, so a recording gap never counts as a stop.
# Settled samples and every sample within the threshold before one are track breaks:
# the arrival closes a journey, the last settled sample opens the next one, and the
# dwell in between belongs to no track.
#
# Distances use a bounding box of the window in equirectangular meters, which keeps the
# check linear in the number of samples however densely a device reports.
#
# The radius is the user's visit radius, so a stop for tracks and a stay for visits
# tolerate the same position noise. A visit radius below the default never makes
# stops stricter: precise visits must not bring back day-long tracks.
#
# Used by:
# - Tracks::Segmentation for bulk track generation
# - Track.segment_points_in_sql for realtime track generation
#
class Tracks::StationaryStops
  DEFAULT_RADIUS_METERS = 100
  MIN_VISIT_STOP_SECONDS = 5 * 60
  METERS_PER_DEGREE = 111_320

  def self.radius_for(user)
    [user.safe_settings.visit_radius_meters, DEFAULT_RADIUS_METERS].max
  end

  # A stop long enough to be a visit ends a track even when it is shorter than the route gap.
  # Each threshold finds its own stops, so a short one never loses the stops of a sparse logger.
  # Below five minutes a slow walk stays within the radius long enough to look like a stop.
  def self.thresholds_for(user, route_gap_seconds = user.safe_settings.minutes_between_routes * 60)
    visit_seconds = [user.safe_settings.visit_min_duration_minutes * 60, MIN_VISIT_STOP_SECONDS].max
    [route_gap_seconds, [route_gap_seconds, visit_seconds].min].uniq
  end

  # samples: [[timestamp, lon, lat], ...] ordered by timestamp; lon and lat may be nil.
  def self.break_indexes(samples, threshold_seconds, radius_meters = DEFAULT_RADIUS_METERS)
    Array(threshold_seconds).map { |threshold| new(samples, threshold, radius_meters).break_indexes }.reduce(:|)
  end

  # Context a caller must load before the first sample it segments.
  def self.history_seconds(threshold_seconds)
    (2 * Array(threshold_seconds).max) + 1
  end

  # A track that starts at a departure must never be joined to the track before it.
  def self.departure?(track, threshold_seconds, radius_meters = nil)
    first_point = track.points.order(:timestamp).first
    return false unless first_point

    Track.stationary_break_point_ids(track.user_id, first_point.timestamp, first_point.timestamp, threshold_seconds,
                                     radius_meters)
         .include?(first_point.id)
  end

  # Realtime adds a stop's first threshold of dwell to the arrival track before the stop
  # can be recognized. Returns those trailing points, keeping the arrival and its journey.
  def self.dwell_tail_point_ids(track, threshold_seconds, radius_meters = nil)
    end_timestamp = track.end_at.to_i
    longest = Array(threshold_seconds).max
    window_start = [track.start_at.to_i, end_timestamp - (2 * longest)].max
    breaks = Track.stationary_break_point_ids(track.user_id, window_start, end_timestamp + longest,
                                              threshold_seconds, radius_meters).to_set
    ids = track.points.order(timestamp: :desc).pluck(:id)
    tail = ids.take_while { |id| breaks.include?(id) }

    ids.size - tail.size >= 2 ? tail : []
  end

  def initialize(samples, threshold_seconds, radius_meters = DEFAULT_RADIUS_METERS)
    @samples = samples
    @threshold_seconds = threshold_seconds
    @radius_meters = radius_meters
  end

  def break_indexes
    settled = settled_flags
    breaks = Set.new
    next_settled_timestamp = nil

    (samples.size - 1).downto(0) do |index|
      next_settled_timestamp = timestamp(index) if settled[index]
      next if next_settled_timestamp.nil?

      breaks << index if next_settled_timestamp - timestamp(index) <= threshold_seconds
    end

    join_stop_fragments(breaks)
  end

  private

  attr_reader :samples, :threshold_seconds, :radius_meters

  # Noise around a stay leaves only some samples settled, which cut the dwell into
  # short tracks. The breaks before such a gap locate the stay. The gap belongs to the
  # stay when every sample in it, and the break after it, lies within the radius of the
  # centre of the stay so far, gap included. A walk that leaves the radius keeps its track.
  def join_stop_fragments(breaks)
    sorted = breaks.sort
    stay_start = sorted.first

    sorted.each_cons(2) do |first, last|
      next if last - first == 1

      center = stay_center(stay_start, last)
      if center && (first + 1..last).all? { |index| near?(center, index) }
        breaks.merge(first + 1...last)
      else
        stay_start = last
      end
    end
    breaks
  end

  def stay_center(from, to)
    count, lon, lat = located_sums[to + 1].zip(located_sums[from]).map { |upto, before| upto - before }
    [lon / count, lat / count] if count.positive?
  end

  def located_sums
    @located_sums ||= samples.each_index.each_with_object([[0, 0.0, 0.0]]) do |index, sums|
      count, lon, lat = sums.last
      sums << (located?(index) ? [count + 1, lon + samples[index][1], lat + samples[index][2]] : [count, lon, lat])
    end
  end

  def near?(center, index)
    return false unless located?(index)

    center_lon, center_lat = center
    _, lon, lat = samples[index]
    east_meters = (lon - center_lon) * METERS_PER_DEGREE * Math.cos(center_lat * Math::PI / 180)
    north_meters = (lat - center_lat) * METERS_PER_DEGREE

    east_meters**2 + north_meters**2 <= radius_meters**2
  end

  def settled_flags
    windows = { lon_min: [], lon_max: [], lat_min: [], lat_max: [] }
    head = 0

    samples.each_index.map do |index|
      head += 1 while timestamp(head) < timestamp(index) - threshold_seconds
      add_to_windows(windows, index) if located?(index)
      windows.each_value { |deque| deque.shift while deque.any? && deque.first[1] < head }

      located?(index) && anchored?(head, index) && within_radius?(index, head - 1, windows)
    end
  end

  def anchored?(head, index)
    return false unless head.positive? && located?(head - 1)

    timestamp(head - 1) >= timestamp(index) - self.class.history_seconds(threshold_seconds)
  end

  # Monotonic deques of [value, index] keep the extreme of each window at the front.
  def add_to_windows(windows, index)
    _, lon, lat = samples[index]
    { lon_min: [lon, :<], lon_max: [lon, :>], lat_min: [lat, :<], lat_max: [lat, :>] }.each do |key, (value, keeps)|
      deque = windows[key]
      deque.pop while deque.any? && !deque.last[0].public_send(keeps, value)
      deque << [value, index]
    end
  end

  def within_radius?(index, anchor_index, windows)
    _, lon, lat = samples[index]
    _, anchor_lon, anchor_lat = samples[anchor_index]
    lon_spread = [[windows[:lon_max][0][0], anchor_lon].max - lon, lon - [windows[:lon_min][0][0], anchor_lon].min].max
    lat_spread = [[windows[:lat_max][0][0], anchor_lat].max - lat, lat - [windows[:lat_min][0][0], anchor_lat].min].max
    east_meters = lon_spread * METERS_PER_DEGREE * Math.cos(lat * Math::PI / 180)
    north_meters = lat_spread * METERS_PER_DEGREE

    east_meters**2 + north_meters**2 <= radius_meters**2
  end

  def located?(index)
    !samples[index][1].nil? && !samples[index][2].nil?
  end

  def timestamp(index)
    samples[index][0]
  end
end
