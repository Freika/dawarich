# frozen_string_literal: true

module TransportationModes
  # Extracts transportation mode data from source-provided activity information.
  # Supports Overland API motion/activity fields and Google Takeout activity types.
  #
  # This extractor checks the motion_data field of points first (new data),
  # falling back to raw_data for backward compatibility with existing points.
  #
  class SourceDataExtractor
    # Overland API motion values mapping
    OVERLAND_MODE_MAP = {
      'driving' => :driving,
      'walking' => :walking,
      'running' => :running,
      'cycling' => :cycling,
      'stationary' => :stationary,
      'automotive' => :driving
    }.freeze

    # Overland activity type mapping
    OVERLAND_ACTIVITY_MAP = {
      'automotive_navigation' => :driving,
      'fitness' => :walking, # Could be running/cycling, but walking is safer default
      'other_navigation' => :driving,
      'other' => :unknown
    }.freeze

    # Overland action type mapping (for visit points, etc.)
    OVERLAND_ACTION_MAP = {
      'visit' => :stationary,
      'depart' => :stationary,
      'arrive' => :stationary
    }.freeze

    # Google Takeout activity type mapping
    GOOGLE_MODE_MAP = {
      'STILL' => :stationary,
      'WALKING' => :walking,
      'ON_FOOT' => :walking,
      'RUNNING' => :running,
      'CYCLING' => :cycling,
      'IN_VEHICLE' => :driving,
      'IN_ROAD_VEHICLE' => :driving,
      'IN_RAIL_VEHICLE' => :train,
      'IN_BUS' => :bus,
      'IN_SUBWAY' => :train,
      'IN_TRAM' => :train,
      'IN_TRAIN' => :train,
      'IN_FERRY' => :boat,
      'SAILING' => :boat,
      'FLYING' => :flying,
      'IN_AIRPLANE' => :flying,
      'MOTORCYCLING' => :motorcycle,
      'UNKNOWN' => :unknown
    }.freeze

    # OwnTracks motion state mapping
    OWNTRACKS_MODE_MAP = {
      0 => :stationary,  # stopped
      1 => :unknown      # moving (could be anything)
    }.freeze

    def initialize(points)
      @points = points
    end

    def call
      return [] if @points.empty?

      # Try to extract mode from each point's raw_data
      point_modes = extract_modes_from_points
      return [] if point_modes.all? { |pm| pm[:mode] == :unknown }

      # Group consecutive points with the same mode into segments
      build_segments_from_point_modes(point_modes)
    end

    private

    def extract_modes_from_points
      @points.map.with_index do |point, index|
        data = point.motion_data.presence || point.raw_data || {}
        mode = extract_mode_from_raw_data(data)
        source = detect_source(data)

        {
          index: index,
          mode: mode,
          source: source,
          confidence: mode == :unknown ? :low : :high
        }
      end
    end

    def extract_mode_from_raw_data(raw_data)
      # Handle nil or non-hash raw_data
      return :unknown unless raw_data.is_a?(Hash)

      # Normalize keys to handle both string and symbol keys
      data = begin
        raw_data.deep_symbolize_keys
      rescue StandardError
        raw_data
      end

      # Try Overland format first (motion array and activity)
      mode = extract_overland_mode(data)
      return mode if mode && mode != :unknown

      # Try Google format (activityRecord or probableActivities)
      mode = extract_google_mode(data)
      return mode if mode && mode != :unknown

      # Try OwnTracks format
      mode = extract_owntracks_mode(data)
      return mode if mode && mode != :unknown

      :unknown
    end

    def extract_overland_mode(data)
      # Skip if data is not a Hash (could be an array from incorrect raw_data format)
      return nil unless data.is_a?(Hash)

      # Check properties.motion for Overland API
      properties = data[:properties] || data

      # Motion is typically an array like ["driving", "stationary"]
      motion = properties[:motion]
      if motion.is_a?(Array) && motion.any?
        # Take the first non-stationary motion if available
        motion.each do |m|
          mapped = OVERLAND_MODE_MAP[m.to_s.downcase]
          return mapped if mapped && mapped != :stationary
        end
        # If only stationary found, return that
        return :stationary if motion.any? { |m| m.to_s.downcase == 'stationary' }
      end

      # Check activity field
      activity = properties[:activity]
      return OVERLAND_ACTIVITY_MAP[activity] || :unknown if activity.is_a?(String)

      # Check action field (for visit points: action=visit means stationary)
      action = properties[:action]
      return OVERLAND_ACTION_MAP[action] if action.is_a?(String) && OVERLAND_ACTION_MAP.key?(action)

      nil
    end

    def extract_google_mode(data)
      # Google Phone Takeout format: activityRecord.probableActivities
      activity_record = data[:activityRecord] || data[:activity_record]
      if activity_record
        activities = activity_record[:probableActivities] || activity_record[:probable_activities]
        return extract_most_probable_google_activity(activities) if activities
      end

      # Google Semantic History format: activities array with activityType
      activities = data[:activities]
      return extract_most_probable_google_activity(activities) if activities.is_a?(Array)

      # Direct activity type
      activity_type = data[:activityType] || data[:activity_type]
      return GOOGLE_MODE_MAP[activity_type.to_s.upcase] || :unknown if activity_type

      nil
    end

    def extract_most_probable_google_activity(activities)
      return nil unless activities.is_a?(Array) && activities.any?

      # Sort by probability/confidence if available
      sorted = activities.sort_by do |a|
        -(a[:probability] || a[:confidence] || 0).to_f
      end

      # Return the highest probability activity that we recognize
      sorted.each do |activity|
        type = activity[:activityType] || activity[:activity_type] || activity[:type]
        next unless type

        mapped = GOOGLE_MODE_MAP[type.to_s.upcase]
        return mapped if mapped && mapped != :unknown
      end

      :unknown
    end

    def extract_owntracks_mode(data)
      # OwnTracks uses 'm' for motion state
      motion_state = data[:m]
      return nil unless motion_state

      OWNTRACKS_MODE_MAP[motion_state.to_i]
    end

    def detect_source(raw_data)
      # Handle nil or non-hash raw_data
      return 'unknown' unless raw_data.is_a?(Hash)

      data = begin
        raw_data.deep_symbolize_keys
      rescue StandardError
        raw_data
      end
      properties = data[:properties] || {}

      # Detect Overland (check for motion, activity, or action fields)
      return 'overland' if properties[:motion] || properties[:activity] || properties[:action]

      # Detect Google
      return 'google' if data[:activityRecord] || data[:activities] || data[:activityType]

      # Detect OwnTracks
      return 'owntracks' if data[:m] || data[:_type] == 'location'

      'unknown'
    end

    def build_segments_from_point_modes(point_modes)
      return [] if point_modes.empty?

      segments = []
      current_segment = {
        mode: point_modes.first[:mode],
        start_index: 0,
        source: point_modes.first[:source],
        confidence: point_modes.first[:confidence],
        point_indices: [0]
      }

      point_modes.each_with_index do |pm, index|
        next if index.zero?

        if pm[:mode] == current_segment[:mode]
          current_segment[:point_indices] << index
        else
          # Finalize current segment
          segments << current_segment

          # Start new segment
          current_segment = {
            mode: pm[:mode],
            start_index: index,
            source: pm[:source],
            confidence: pm[:confidence],
            point_indices: [index]
          }
        end
      end

      # Add last segment
      segments << current_segment

      # Merge unknown segments into adjacent known segments to avoid gaps
      merged_segments = merge_unknown_into_adjacent_segments(segments)

      # Finalize and return only known segments
      merged_segments.map { |seg| finalize_segment(seg) }
    end

    # Merges unknown segments into adjacent known segments to ensure contiguous coverage.
    # Unknown points are absorbed by the previous segment (preferred) or next segment.
    # After merging unknowns, also merges consecutive segments of the same mode.
    # This prevents gaps in segment visualization on the map.
    #
    # @param segments [Array<Hash>] Raw segments with :mode, :start_index, :point_indices, etc.
    # @return [Array<Hash>] Segments with unknown points merged into adjacent segments
    def merge_unknown_into_adjacent_segments(segments)
      return segments if segments.empty?
      return segments if segments.none? { |s| s[:mode] == :unknown }

      # First pass: absorb unknown segments into adjacent known segments
      after_unknown_merge = []

      segments.each_with_index do |segment, idx|
        if segment[:mode] == :unknown
          # Try to merge into previous segment
          if after_unknown_merge.any?
            # Extend previous segment to include this unknown segment's points
            after_unknown_merge.last[:point_indices].concat(segment[:point_indices])
            after_unknown_merge.last[:confidence] = :medium # Downgrade confidence since we're inferring
          elsif segments[idx + 1] && segments[idx + 1][:mode] != :unknown
            # No previous segment - prepend to next segment
            next_seg = segments[idx + 1]
            next_seg[:point_indices] = segment[:point_indices] + next_seg[:point_indices]
            next_seg[:start_index] = segment[:start_index]
            next_seg[:confidence] = :medium
          else
            # Edge case: all segments are unknown, keep as-is
            after_unknown_merge << segment
          end
        else
          after_unknown_merge << segment
        end
      end

      # Second pass: merge consecutive segments of the same mode
      # (This can happen when an unknown segment was between two same-mode segments)
      merge_consecutive_same_mode_segments(after_unknown_merge)
    end

    # Merges consecutive segments that have the same transportation mode.
    # This consolidates fragmented segments that were split by unknown points.
    #
    # @param segments [Array<Hash>] Segments after unknown merging
    # @return [Array<Hash>] Consolidated segments
    def merge_consecutive_same_mode_segments(segments)
      return segments if segments.size < 2

      result = []

      segments.each do |segment|
        if result.any? && result.last[:mode] == segment[:mode]
          # Merge into previous segment of same mode
          result.last[:point_indices].concat(segment[:point_indices])
          # Keep the lower confidence (medium if either was medium)
          result.last[:confidence] = :medium if segment[:confidence] == :medium || result.last[:confidence] == :medium
        else
          result << segment
        end
      end

      result
    end

    def finalize_segment(segment)
      start_idx = segment[:start_index]
      end_idx = segment[:point_indices].last

      # Calculate segment statistics
      segment_points = @points[start_idx..end_idx]
      distance = calculate_segment_distance(segment_points)
      duration = calculate_segment_duration(segment_points)
      avg_speed = calculate_avg_speed(distance, duration)
      max_speed = calculate_max_speed(segment_points)

      {
        mode: segment[:mode],
        start_index: start_idx,
        end_index: end_idx,
        distance: distance,
        duration: duration,
        avg_speed: avg_speed,
        max_speed: max_speed,
        avg_acceleration: nil, # Not calculated for source data
        confidence: segment[:confidence],
        source: segment[:source]
      }
    end

    def calculate_segment_distance(points)
      return 0 if points.size < 2

      total = 0
      points.each_cons(2) do |p1, p2|
        total += begin
          p1.distance_to(p2, :m)
        rescue StandardError
          0
        end
      end
      total.round
    rescue StandardError
      0
    end

    def calculate_segment_duration(points)
      return 0 if points.size < 2

      points.last.timestamp - points.first.timestamp
    end

    def calculate_avg_speed(distance_m, duration_s)
      return 0.0 if duration_s.nil? || duration_s <= 0 || distance_m.nil?

      speed_mps = distance_m.to_f / duration_s
      (speed_mps * 3.6).round(2) # Convert m/s to km/h
    end

    def calculate_max_speed(points)
      velocities = points.map do |p|
        v = p.velocity
        next nil unless v

        # Velocity is stored as string in m/s
        v.to_f * 3.6 # Convert to km/h
      end.compact

      velocities.max&.round(2)
    end
  end
end
