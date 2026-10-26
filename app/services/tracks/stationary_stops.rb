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
  METERS_PER_DEGREE = 111_320

  # samples: [[timestamp, lon, lat], ...] ordered by timestamp; lon and lat may be nil.
  def self.break_indexes(samples, threshold_seconds, radius_meters = DEFAULT_RADIUS_METERS)
    new(samples, threshold_seconds, radius_meters).break_indexes
  end

  def self.radius_for(user)
    [user.safe_settings.visit_radius_meters, DEFAULT_RADIUS_METERS].max
  end

  # Context a caller must load before the first sample it segments.
  def self.history_seconds(threshold_seconds)
    (2 * threshold_seconds) + 1
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
    window_start = [track.start_at.to_i, end_timestamp - (2 * threshold_seconds)].max
    breaks = Track.stationary_break_point_ids(track.user_id, window_start, end_timestamp + threshold_seconds,
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
  # short tracks. The break before such a gap is always a settled sample, so its
  # threshold window locates the stay. The gap belongs to the stay when every sample
  # in it, and the break after it, lies within the radius of that window's centre.
  # A walk that leaves the radius around the stay keeps its track.
  def join_stop_fragments(breaks)
    breaks.sort.each_cons(2) do |first, last|
      next if last - first == 1

      center = stay_center(first)
      next unless center && (first + 1..last).all? { |index| near?(center, index) }

      breaks.merge(first + 1...last)
    end
    breaks
  end

  def stay_center(settled_index)
    from = samples.bsearch_index { |row| row[0] >= timestamp(settled_index) - threshold_seconds }
    located = (from..settled_index).select { |index| located?(index) }
    return if located.empty?

    [located.sum { |index| samples[index][1] } / located.size, located.sum { |index| samples[index][2] } / located.size]
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
