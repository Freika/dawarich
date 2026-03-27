# frozen_string_literal: true

class Points::AnomalyFilter
  ACCURACY_THRESHOLD = 100       # meters
  MAX_SPEED_KMH = 1000           # km/h — floor for speed threshold
  SPEED_MULTIPLIER = 3           # threshold = max(floor, median * multiplier)
  CONTEXT_POINTS = 5             # extra points for speed context at boundaries

  def initialize(user_id, start_time, end_time)
    @user_id = user_id
    @start_time = start_time
    @end_time = end_time
  end

  def call
    count = 0
    count += filter_by_accuracy
    count += filter_by_speed
    count
  end

  private

  # Pass 1: Mark points with accuracy > threshold
  def filter_by_accuracy
    Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
         .not_anomaly
         .where.not(accuracy: nil)
         .where('accuracy > ?', ACCURACY_THRESHOLD)
         .update_all(anomaly: true)
  end

  # Pass 2: Speed-based sandwich test
  def filter_by_speed
    points, main_points = fetch_points_with_context
    return 0 if points.size < 3

    point_ids = points.map(&:id)
    speeds_by_point = calculate_all_speeds(point_ids)
    return 0 if speeds_by_point.empty?

    all_speeds = speeds_by_point.values.flat_map { |h| [h[:incoming], h[:outgoing]] }.compact
    return 0 if all_speeds.empty?

    floor_mps = MAX_SPEED_KMH / 3.6
    # Compute median from non-extreme speeds only so outliers don't inflate the threshold
    normal_speeds = all_speeds.select { |s| s <= floor_mps }
    median = normal_speeds.empty? ? 0.0 : median_speed(normal_speeds)
    threshold = [floor_mps, median * SPEED_MULTIPLIER].max

    # Only check points in the main range (not context points)
    main_range_ids = main_points.map(&:id).to_set

    anomaly_ids = []
    points.each_with_index do |point, i|
      next if i.zero? || i >= points.size - 1
      next unless main_range_ids.include?(point.id)

      speed_in = speeds_by_point.dig(point.id, :incoming)
      speed_out = speeds_by_point.dig(point.id, :outgoing)
      next if speed_in.nil? || speed_out.nil?

      anomaly_ids << point.id if speed_in > threshold && speed_out > threshold
    end

    return 0 if anomaly_ids.empty?

    Point.where(id: anomaly_ids).update_all(anomaly: true)
  end

  def fetch_points_with_context
    before_ctx = Point.where(user_id: @user_id).not_anomaly
                      .where('timestamp < ?', @start_time)
                      .order(timestamp: :desc).limit(CONTEXT_POINTS)
                      .select(:id, :lonlat, :timestamp).to_a.reverse

    main = Point.where(user_id: @user_id, timestamp: @start_time..@end_time)
                .not_anomaly.order(:timestamp)
                .select(:id, :lonlat, :timestamp).to_a

    after_ctx = Point.where(user_id: @user_id).not_anomaly
                     .where('timestamp > ?', @end_time)
                     .order(:timestamp).limit(CONTEXT_POINTS)
                     .select(:id, :lonlat, :timestamp).to_a

    [before_ctx + main + after_ctx, main]
  end

  # Single CTE query: compute distance and time diff for ALL consecutive pairs
  def calculate_all_speeds(point_ids)
    return {} if point_ids.empty?

    ids_literal = point_ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(',')

    sql = <<~SQL
      WITH ordered_points AS (
        SELECT id, lonlat, timestamp,
               LAG(id) OVER (ORDER BY timestamp, id) AS prev_id,
               LAG(lonlat) OVER (ORDER BY timestamp, id) AS prev_lonlat,
               LAG(timestamp) OVER (ORDER BY timestamp, id) AS prev_timestamp
        FROM points
        WHERE id = ANY(ARRAY[#{ids_literal}])
      )
      SELECT id, prev_id,
             CASE WHEN (timestamp - prev_timestamp) > 0
                  THEN ST_Distance(lonlat::geography, prev_lonlat::geography)
                       / (timestamp - prev_timestamp)
                  ELSE NULL END AS speed_mps
      FROM ordered_points
      WHERE prev_id IS NOT NULL
    SQL

    result = {}
    Point.connection.execute(sql).each do |row|
      speed = row['speed_mps']&.to_f
      prev_id = row['prev_id'].to_i
      curr_id = row['id'].to_i

      result[prev_id] ||= {}
      result[prev_id][:outgoing] = speed

      result[curr_id] ||= {}
      result[curr_id][:incoming] = speed
    end
    result
  end

  def median_speed(speeds)
    sorted = speeds.compact.sort
    return 0.0 if sorted.empty?

    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
