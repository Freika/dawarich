# frozen_string_literal: true

module TransportationModes
  # Infers transportation mode from movement patterns when source data
  # doesn't provide activity information.
  #
  # Uses speed and acceleration analysis to detect mode changes and
  # classify segments of movement.
  #
  class MovementAnalyzer
    # Minimum segment duration in seconds to be considered valid
    MIN_SEGMENT_DURATION = 60

    # Minimum number of points for a valid segment
    MIN_SEGMENT_POINTS = 2

    # Speed change threshold to consider a mode change (km/h)
    # Increased to reduce noise-induced segment splits
    SPEED_CHANGE_THRESHOLD = 25

    # Time gap that indicates a mode change (seconds)
    TIME_GAP_THRESHOLD = 180

    # Smoothing window size for speed averaging
    SMOOTHING_WINDOW = 5

    def initialize(track, points)
      @track = track
      @points = points.sort_by(&:timestamp)
    end

    def call
      return [] if @points.size < MIN_SEGMENT_POINTS

      # 1. Calculate movement metrics for each point pair
      movement_data = calculate_movement_metrics

      # 2. Detect segment boundaries based on speed/acceleration changes
      segment_boundaries = detect_segment_boundaries(movement_data)

      # 3. Build and classify segments
      build_classified_segments(segment_boundaries, movement_data)
    end

    private

    def calculate_movement_metrics
      metrics = []

      @points.each_cons(2).with_index do |(p1, p2), idx|
        time_diff = p2.timestamp - p1.timestamp
        next if time_diff <= 0

        # Calculate distance between points
        distance = calculate_distance(p1, p2)

        # Calculate speed (prefer stored velocity, fall back to calculated)
        speed_mps = get_speed(p1, p2, distance, time_diff)
        speed_kmh = speed_mps * 3.6

        # Calculate acceleration (change in speed over time)
        prev_speed = metrics.any? ? metrics.last[:speed_mps] : speed_mps
        acceleration = (speed_mps - prev_speed) / time_diff

        metrics << {
          index: idx,
          point1: p1,
          point2: p2,
          distance: distance,
          time_diff: time_diff,
          speed_mps: speed_mps,
          speed_kmh: speed_kmh,
          acceleration: acceleration
        }
      end

      metrics
    end

    def calculate_distance(p1, p2)
      # Use PostGIS distance if available
      if p1.respond_to?(:distance_to)
        begin
          p1.distance_to(p2, :m)
        rescue StandardError
          haversine_distance(p1, p2)
        end
      else
        haversine_distance(p1, p2)
      end
    end

    def haversine_distance(p1, p2)
      lat1_deg = p1.latitude || extract_lat(p1)
      lat2_deg = p2.latitude || extract_lat(p2)
      lon1_deg = p1.longitude || extract_lon(p1)
      lon2_deg = p2.longitude || extract_lon(p2)

      # Return 0 if any coordinate is missing
      return 0 if lat1_deg.nil? || lat2_deg.nil? || lon1_deg.nil? || lon2_deg.nil?

      lat1 = to_radians(lat1_deg)
      lat2 = to_radians(lat2_deg)
      lon1 = to_radians(lon1_deg)
      lon2 = to_radians(lon2_deg)

      dlat = lat2 - lat1
      dlon = lon2 - lon1

      a = Math.sin(dlat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlon / 2)**2
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

      6_371_000 * c # Earth radius in meters
    end

    def extract_lat(point)
      return nil unless point.lonlat

      # Extract from PostGIS point or WKT string
      if point.lonlat.respond_to?(:y)
        point.lonlat.y
      elsif point.lonlat.is_a?(String)
        # Parse WKT string like "POINT(lon lat)"
        match = point.lonlat.match(/POINT\s*\(\s*[\d.-]+\s+([\d.-]+)\s*\)/i)
        match[1].to_f if match
      end
    rescue StandardError
      nil
    end

    def extract_lon(point)
      return nil unless point.lonlat

      # Extract from PostGIS point or WKT string
      if point.lonlat.respond_to?(:x)
        point.lonlat.x
      elsif point.lonlat.is_a?(String)
        # Parse WKT string like "POINT(lon lat)"
        match = point.lonlat.match(/POINT\s*\(\s*([\d.-]+)\s+[\d.-]+\s*\)/i)
        match[1].to_f if match
      end
    rescue StandardError
      nil
    end

    def to_radians(degrees)
      degrees.to_f * Math::PI / 180
    end

    def get_speed(_p1, p2, distance, time_diff)
      # Prefer stored velocity from GPS
      if p2.velocity.present?
        stored_speed = p2.velocity.to_f
        return stored_speed if stored_speed >= 0
      end

      # Calculate from distance and time
      return 0 if time_diff <= 0

      distance / time_diff
    end

    def detect_segment_boundaries(movement_data)
      return [{ start: 0, end: movement_data.size - 1 }] if movement_data.size < 3

      boundaries = []
      current_start = 0

      # Use smoothed speed to reduce noise
      smoothed_speeds = smooth_speeds(movement_data.map { |m| m[:speed_kmh] }, window: SMOOTHING_WINDOW)

      movement_data.each_with_index do |metric, idx|
        next if idx.zero?

        prev_metric = movement_data[idx - 1]
        is_boundary = false

        # Check for time gap (indicates stop/start)
        is_boundary = true if metric[:time_diff] > TIME_GAP_THRESHOLD

        # Check for significant speed change
        speed_diff = (smoothed_speeds[idx] - smoothed_speeds[idx - 1]).abs
        is_boundary = true if speed_diff > SPEED_CHANGE_THRESHOLD

        # Check for sustained acceleration spike (mode change indicator)
        # Require higher threshold to avoid GPS noise
        is_boundary = true if metric[:acceleration].abs > 3.0 && prev_metric[:acceleration].abs < 0.3

        if is_boundary && idx > current_start
          boundaries << { start: current_start, end: idx - 1 }
          current_start = idx
        end
      end

      # Add final segment
      boundaries << { start: current_start, end: movement_data.size - 1 }

      # Merge very short segments
      merge_short_segments(boundaries, movement_data)
    end

    def smooth_speeds(speeds, window: 3)
      return speeds if speeds.size < window

      speeds.map.with_index do |_speed, idx|
        start_idx = [0, idx - window / 2].max
        end_idx = [speeds.size - 1, idx + window / 2].min
        window_speeds = speeds[start_idx..end_idx]
        window_speeds.sum / window_speeds.size.to_f
      end
    end

    def merge_short_segments(boundaries, movement_data)
      return boundaries if boundaries.size <= 1

      merged = []
      current = boundaries.first

      boundaries[1..].each do |segment|
        segment_duration = calculate_boundary_duration(current, movement_data)

        if segment_duration < MIN_SEGMENT_DURATION
          # Merge with next segment
          current = { start: current[:start], end: segment[:end] }
        else
          merged << current
          current = segment
        end
      end

      merged << current
      merged
    end

    def calculate_boundary_duration(boundary, movement_data)
      return 0 if boundary[:start] > boundary[:end]

      start_metric = movement_data[boundary[:start]]
      end_metric = movement_data[boundary[:end]]

      return 0 unless start_metric && end_metric

      end_metric[:point2].timestamp - start_metric[:point1].timestamp
    end

    def build_classified_segments(boundaries, movement_data)
      segments = boundaries.map do |boundary|
        build_segment(boundary, movement_data)
      end.compact

      # Merge consecutive segments with the same mode
      merge_same_mode_segments(segments)
    end

    # Merges consecutive segments that have the same transportation mode
    def merge_same_mode_segments(segments)
      return segments if segments.size <= 1

      merged = []
      current = segments.first

      segments[1..].each do |segment|
        if segment[:mode] == current[:mode]
          # Merge: combine stats
          current = merge_two_segments(current, segment)
        else
          merged << current
          current = segment
        end
      end

      merged << current
      merged
    end

    def merge_two_segments(seg1, seg2)
      {
        mode: seg1[:mode],
        start_index: seg1[:start_index],
        end_index: seg2[:end_index],
        distance: (seg1[:distance] || 0) + (seg2[:distance] || 0),
        duration: (seg1[:duration] || 0) + (seg2[:duration] || 0),
        avg_speed: weighted_avg_speed(seg1, seg2),
        max_speed: [seg1[:max_speed] || 0, seg2[:max_speed] || 0].max,
        avg_acceleration: weighted_avg_accel(seg1, seg2),
        confidence: lower_confidence(seg1[:confidence], seg2[:confidence]),
        source: seg1[:source]
      }
    end

    def weighted_avg_speed(seg1, seg2)
      d1 = seg1[:duration] || 1
      d2 = seg2[:duration] || 1
      s1 = seg1[:avg_speed] || 0
      s2 = seg2[:avg_speed] || 0
      ((s1 * d1) + (s2 * d2)) / (d1 + d2).to_f
    end

    def weighted_avg_accel(seg1, seg2)
      d1 = seg1[:duration] || 1
      d2 = seg2[:duration] || 1
      a1 = seg1[:avg_acceleration] || 0
      a2 = seg2[:avg_acceleration] || 0
      ((a1 * d1) + (a2 * d2)) / (d1 + d2).to_f
    end

    def lower_confidence(c1, c2)
      order = { high: 3, medium: 2, low: 1 }
      v1 = order[c1&.to_sym] || 1
      v2 = order[c2&.to_sym] || 1
      v1 <= v2 ? c1 : c2
    end

    def build_segment(boundary, movement_data)
      segment_metrics = movement_data[boundary[:start]..boundary[:end]]
      return nil if segment_metrics.nil? || segment_metrics.empty?

      # Calculate segment statistics with nil protection
      speeds = segment_metrics.map { |m| m[:speed_kmh] }.compact
      accelerations = segment_metrics.map { |m| m[:acceleration] }.compact
      distances = segment_metrics.map { |m| m[:distance] }.compact
      durations = segment_metrics.map { |m| m[:time_diff] }.compact

      return nil if speeds.empty? || distances.empty? || durations.empty?

      avg_speed = speeds.sum / speeds.size.to_f
      max_speed = speeds.max || 0
      avg_acceleration = accelerations.any? ? accelerations.map(&:abs).sum / accelerations.size.to_f : 0
      total_distance = distances.sum
      total_duration = durations.sum

      # Classify the segment
      classifier = ModeClassifier.new(
        avg_speed_kmh: avg_speed,
        max_speed_kmh: max_speed,
        avg_acceleration: avg_acceleration,
        duration: total_duration
      )

      mode = classifier.classify
      confidence = classifier.confidence

      {
        mode: mode,
        start_index: boundary[:start],
        end_index: boundary[:end] + 1, # +1 because end_index in metrics refers to point pairs
        distance: total_distance.round,
        duration: total_duration.round,
        avg_speed: avg_speed.round(2),
        max_speed: max_speed.round(2),
        avg_acceleration: avg_acceleration.round(4),
        confidence: confidence,
        source: 'inferred'
      }
    end
  end
end
