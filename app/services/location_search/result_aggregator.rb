# frozen_string_literal: true

module LocationSearch
  class ResultAggregator
    include ActionView::Helpers::TextHelper

    # Time threshold for grouping consecutive points into visits (minutes)
    VISIT_TIME_THRESHOLD = 30

    def group_points_into_visits(points)
      return [] if points.empty?

      # Sort points by timestamp to handle unordered input
      sorted_points = points.sort_by { |p| p[:timestamp] }

      visits = []
      current_visit_points = []

      sorted_points.each do |point|
        if current_visit_points.empty? || within_visit_threshold?(current_visit_points.last, point)
          current_visit_points << point
        else
          # Finalize current visit and start a new one
          visits << create_visit_from_points(current_visit_points) if current_visit_points.any?
          current_visit_points = [point]
        end
      end

      # Don't forget the last visit
      visits << create_visit_from_points(current_visit_points) if current_visit_points.any?

      visits.sort_by { |visit| -visit[:timestamp] } # Most recent first
    end

    private

    def within_visit_threshold?(previous_point, current_point)
      time_diff = (current_point[:timestamp] - previous_point[:timestamp]).abs / 60.0 # minutes
      time_diff <= VISIT_TIME_THRESHOLD
    end

    def create_visit_from_points(points)
      return nil if points.empty?

      # Sort points by timestamp to get chronological order
      sorted_points = points.sort_by { |p| p[:timestamp] }
      first_point = sorted_points.first
      last_point = sorted_points.last

      # Calculate visit duration
      duration_minutes =
        if sorted_points.any?
          ((last_point[:timestamp] - first_point[:timestamp]) / 60.0).round
        else
          # Single point visit - estimate based on typical stay time
          15 # minutes
        end

      # Find the most accurate point (lowest accuracy value means higher precision)
      most_accurate_point = points.min_by { |p| p[:accuracy] || 999_999 }

      # Calculate average distance from search center
      average_distance = (points.sum { |p| p[:distance_meters] } / points.length).round(2)

      {
        timestamp: first_point[:timestamp],
        date: first_point[:date],
        coordinates: most_accurate_point[:coordinates],
        distance_meters: average_distance,
        duration_estimate: format_duration(duration_minutes),
        points_count: points.length,
        accuracy_meters: most_accurate_point[:accuracy],
        visit_details: {
          start_time: first_point[:date],
          end_time: last_point[:date],
          duration_minutes: duration_minutes,
          city: most_accurate_point[:city],
          country: most_accurate_point[:country],
          altitude_range: calculate_altitude_range(points)
        }
      }
    end

    def format_duration(minutes)
      return "~#{pluralize(minutes, 'minute')}" if minutes < 60

      hours = minutes / 60
      remaining_minutes = minutes % 60

      if remaining_minutes.zero?
        "~#{pluralize(hours, 'hour')}"
      else
        "~#{pluralize(hours, 'hour')} #{pluralize(remaining_minutes, 'minute')}"
      end
    end

    def calculate_altitude_range(points)
      altitudes = points.map { |p| p[:altitude] }.compact
      return nil if altitudes.empty?

      min_altitude = altitudes.min
      max_altitude = altitudes.max

      if min_altitude == max_altitude
        "#{min_altitude}m"
      else
        "#{min_altitude}m - #{max_altitude}m"
      end
    end
  end
end
