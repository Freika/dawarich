# frozen_string_literal: true

class Points::OutlierDetector
  MAX_TIME_GAP_SECONDS = 3600 # 1 hour — skip pairs with gaps larger than this
  BATCH_SIZE = 5000

  attr_reader :user, :start_at, :end_at

  def initialize(user, start_at: nil, end_at: nil)
    @user = user
    @start_at = start_at
    @end_at = end_at
  end

  # Returns the number of points newly flagged as outliers
  def call
    total_flagged = 0

    points_scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      outlier_ids = detect_outliers_in_batch(batch)
      next if outlier_ids.empty?

      Point.where(id: outlier_ids).update_all(outlier: true)
      total_flagged += outlier_ids.size
    end

    total_flagged
  end

  private

  def max_speed_kmh
    @max_speed_kmh ||= user.safe_settings.max_speed_kmh
  end

  def points_scope
    scope = user.points.where(outlier: false).order(:timestamp)
    scope = scope.where('timestamp >= ?', start_at.to_i) if start_at
    scope = scope.where('timestamp <= ?', end_at.to_i) if end_at
    scope.select(:id, :lonlat, :timestamp)
  end

  def detect_outliers_in_batch(points)
    outlier_ids = []
    i = 0

    while i < points.size - 1
      current = points[i]
      next_point = points[i + 1]

      speed = implied_speed(current, next_point)

      if speed && speed > max_speed_kmh
        # Suspected outlier — apply sandwich resolution
        if sandwich_confirms_outlier?(points, i)
          outlier_ids << next_point.id
          # Skip the outlier and continue from the point after it
          i += 2
          next
        end
      end

      i += 1
    end

    outlier_ids
  end

  # Check if skipping the suspected outlier (at index+1) produces a reasonable
  # speed between points[index] and points[index+2].
  # If yes, the middle point is confirmed as an outlier.
  # If there is no point after the suspect, flag it anyway (single-neighbor check).
  def sandwich_confirms_outlier?(points, index)
    after_index = index + 2

    # No point after suspect — flag based on single-neighbor speed alone
    return true if after_index >= points.size

    before = points[index]
    after = points[after_index]

    skip_speed = implied_speed(before, after)

    # If skipping the suspect produces reasonable speed, it's the outlier
    return true if skip_speed.nil? || skip_speed <= max_speed_kmh

    # Both paths are unreasonable — don't flag (could be a real location change
    # with missing intermediate data)
    false
  end

  # Calculate implied speed in km/h between two points.
  # Returns nil if time gap exceeds MAX_TIME_GAP_SECONDS (meaningless measurement).
  def implied_speed(point_a, point_b)
    time_delta = (point_b.timestamp - point_a.timestamp).abs.to_f

    return nil if time_delta == 0
    return nil if time_delta > MAX_TIME_GAP_SECONDS

    distance_km = Geocoder::Calculations.distance_between(
      [point_a.lat, point_a.lon],
      [point_b.lat, point_b.lon],
      units: :km
    )

    return nil unless distance_km.finite?

    hours = time_delta / 3600.0
    distance_km / hours
  end
end
