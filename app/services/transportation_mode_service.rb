# frozen_string_literal: true

class TransportationModeService
  MODES = {
    walking: { min: 0, max: 7 },      # km/h
    running: { min: 7, max: 25 },
    bicycle: { min: 10, max: 45 },
    motorbike: { min: 20, max: 150 },
    car: { min: 20, max: 200 },       # car/taxi/bus
    train: { min: 20, max: 300 },
    boat: { min: 5, max: 80 },        # ferry/boat
    plane: { min: 200, max: 1000 }
  }

  RESTRICTED_MODES = {
    "highway" => [:walking, :running],
    "railway" => [:walking, :running, :bicycle, :motorbike, :car, :boat],
    "water" => [:walking, :running, :bicycle, :motorbike, :car, :train],
    "aeroway" => [:walking, :running, :bicycle, :motorbike, :car, :train, :boat]
  }

  def initialize(points)
    @points = points.sort_by(&:timestamp).reject { |p| p.velocity&.to_f&.negative? }
    @points = calculate_missing_velocities(@points)
  end

  def analyze
    return [] if @points.empty?

    point_results = analyze_points
    group_into_segments(point_results)
  end

  private

  def analyze_points
    results = []
    previous_mode = nil
    consecutive_same_mode_count = 0

    @points.each_with_index do |point, index|
      # Get initial mode based on speed
      speed_km_h = point.velocity.to_f * 3.6 # Convert m/s to km/h
      possible_modes = modes_by_speed(speed_km_h)

      # Refine by geocoding data if available
      favored_mode = nil
      if point.reverse_geocoded?
        restricted, favored_mode = restricted_modes_at_location(point)
        possible_modes -= restricted if restricted.any?
      end

      # Consider road type priority if available
      if favored_mode && possible_modes.include?(favored_mode)
        chosen_mode = favored_mode
      # Consider previous mode for consistency (avoid jumping)
      elsif previous_mode && possible_modes.include?(previous_mode)
        # Stick with previous mode if it's still possible
        # Increase confidence as we get more consecutive points with same mode
        chosen_mode = previous_mode
        consecutive_same_mode_count += 1
      elsif previous_mode && index > 0 && consecutive_same_mode_count < 3
        # Try to avoid abrupt changes by preferring modes close to previous
        # But only if we haven't established a strong pattern yet
        prev_point = @points[index - 1]
        prev_speed = prev_point.velocity.to_f * 3.6
        chosen_mode = best_consistent_mode(possible_modes, previous_mode, speed_km_h, prev_speed)
      else
        # Pick most likely mode from possible ones
        chosen_mode = most_likely_mode(possible_modes, speed_km_h)
      end

      # Reset counter if mode changes
      if previous_mode != chosen_mode
        consecutive_same_mode_count = 0
      end

      previous_mode = chosen_mode
      results << { point: point, mode: chosen_mode }
    end

    # Post-processing: fix isolated mode changes (car-bicycle-car pattern)
    smooth_isolated_mode_changes(results)
  end

  def group_into_segments(point_results)
    segments = []
    current_segment = nil

    point_results.each do |result|
      point = result[:point]
      mode = result[:mode]
      time = Time.zone.at(point.timestamp)
      speed_km_h = point.velocity.to_f * 3.6 # Convert m/s to km/h

      if current_segment.nil? || current_segment[:mode] != mode
        # Close previous segment if exists
        if current_segment
          end_time = Time.zone.at(point_results[point_results.index(result) - 1][:point].timestamp)
          current_segment[:ended_at] = end_time
          current_segment[:minutes] = ((end_time - current_segment[:started_at]) / 60).round(1)
        end

        # Start new segment
        current_segment = {
          started_at: time,
          ended_at: nil,
          mode: mode,
          minutes: nil,
          speed_range: {
            min: speed_km_h,
            max: speed_km_h,
            avg: speed_km_h
          }
        }
        segments << current_segment
      else
        # Update speed range for current segment
        current_segment[:speed_range][:min] = [current_segment[:speed_range][:min], speed_km_h].min
        current_segment[:speed_range][:max] = [current_segment[:speed_range][:max], speed_km_h].max

        # Update running average (simplified approach)
        segment_points = point_results.select { |r| r[:mode] == mode &&
                                              r[:point].timestamp >= current_segment[:started_at].to_i &&
                                              r[:point].timestamp <= point.timestamp }
        speeds = segment_points.map { |r| r[:point].velocity.to_f * 3.6 }
        current_segment[:speed_range][:avg] = (speeds.sum / speeds.size).round(1) if speeds.any?
      end
    end

    # Close the last segment
    if current_segment && current_segment[:ended_at].nil?
      last_point = point_results.last[:point]
      end_time = Time.zone.at(last_point.timestamp)
      current_segment[:ended_at] = end_time
      current_segment[:minutes] = ((end_time - current_segment[:started_at]) / 60).round(1)
    end

    # Filter out segments with 0 duration
    segments.reject { |segment| segment[:minutes] == 0 }
  end

  def calculate_missing_velocities(points)
    points.each_with_index do |point, index|
      next if point.velocity.present? && point.velocity.to_f >= 0

      if index > 0
        previous_point = points[index - 1]
        time_diff = point.timestamp - previous_point.timestamp

        # Skip if points have identical timestamps
        if time_diff <= 0
          point.velocity.to_f = 0
          next
        end

        # Calculate distance between points in meters
        distance = previous_point.distance_to(point) * 1000

        # Calculate velocity in m/s
        point.velocity&.to_f = distance / time_diff
      else
        # For the first point with nil velocity, look ahead if possible
        if index < points.length - 1
          next_point = points[index + 1]
          time_diff = next_point.timestamp - point.timestamp

          if time_diff > 0
            distance = point.distance_to(next_point) * 1000
            point.velocity&.to_f = distance / time_diff
          else
            point.velocity&.to_f = 0
          end
        else
          # If this is the only point, default to 0
          point.velocity&.to_f = 0
        end
      end
    end

    points
  end

  def modes_by_speed(speed_km_h)
    MODES.select { |_, range| speed_km_h.between?(range[:min], range[:max]) }.keys
  end

  def restricted_modes_at_location(point)
    restricted = []
    favored_mode = nil

    # Use Geocoder to get details about location type
    results = Geocoder.search([point.lat, point.lon]).first
    return [restricted, favored_mode] unless results && results.data

    data = results.data

    # Check for highways/roads and favor car on them
    if data["highway"]
      if ["motorway", "trunk", "primary", "secondary", "tertiary", "residential", "unclassified"].include?(data["highway"])
        favored_mode = :car
      end

      # Restrict walking/running on major highways
      if ["motorway", "trunk", "primary"].include?(data["highway"])
        restricted += RESTRICTED_MODES["highway"]
      end
    end

    # Favor walking on pedestrian ways
    if data["highway"] && ["pedestrian", "footway", "steps", "path"].include?(data["highway"])
      favored_mode = :walking
    end

    # Check for railways and favor train
    if data["railway"] || (data["infrastructure"] && data["infrastructure"].include?("railway"))
      restricted += RESTRICTED_MODES["railway"]
      favored_mode = :train if data["railway"] == "rail"
    end

    # Check for water bodies and favor boat
    if data["natural"] == "water" || data["water"] || data["waterway"]
      restricted += RESTRICTED_MODES["water"]
      favored_mode = :boat
    end

    # Check for airports/airfields and favor plane
    if data["aeroway"]
      restricted += RESTRICTED_MODES["aeroway"]
      favored_mode = :plane if data["aeroway"] == "runway" || data["aeroway"] == "taxiway"
    end

    [restricted.uniq, favored_mode]
  end

  def best_consistent_mode(possible_modes, previous_mode, current_speed, previous_speed)
    return possible_modes.first if possible_modes.size == 1

    # If speed delta is small, prefer the previous mode's "family"
    speed_delta = (current_speed - previous_speed).abs

    if speed_delta < 10
      # Group similar modes
      land_vehicles = [:car, :motorbike]
      human_powered = [:walking, :running, :bicycle]

      if land_vehicles.include?(previous_mode) && (possible_modes & land_vehicles).any?
        return (possible_modes & land_vehicles).first
      elsif human_powered.include?(previous_mode) && (possible_modes & human_powered).any?
        return (possible_modes & human_powered).first
      end
    end

    # Otherwise pick the mode closest to current speed's midpoint in its range
    most_likely_mode(possible_modes, current_speed)
  end

  def most_likely_mode(possible_modes, speed_km_h)
    return possible_modes.first if possible_modes.size == 1

    # Find the mode whose speed range midpoint is closest to the current speed
    possible_modes.min_by do |mode|
      range = MODES[mode]
      midpoint = (range[:min] + range[:max]) / 2.0
      (speed_km_h - midpoint).abs
    end
  end

  def smooth_isolated_mode_changes(results)
    # Minimum segment length (in points) to keep
    min_segment_length = 3

    # Identify segments
    segments = []
    current_segment = { mode: results.first[:mode], start_idx: 0, end_idx: 0 }

    results.each_with_index do |result, idx|
      if result[:mode] == current_segment[:mode]
        current_segment[:end_idx] = idx
      else
        segments << current_segment
        current_segment = { mode: result[:mode], start_idx: idx, end_idx: idx }
      end
    end
    segments << current_segment

    # Fix short segments sandwiched between the same mode
    segments.each_with_index do |segment, idx|
      next if idx == 0 || idx == segments.size - 1
      prev_segment = segments[idx - 1]
      next_segment = segments[idx + 1]

      # If short segment is between two segments of the same mode, convert it
      if segment[:end_idx] - segment[:start_idx] + 1 < min_segment_length &&
         prev_segment[:mode] == next_segment[:mode]
        (segment[:start_idx]..segment[:end_idx]).each do |i|
          results[i][:mode] = prev_segment[:mode]
        end
      end
    end

    results
  end
end
