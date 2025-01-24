# frozen_string_literal: true

class Tracks::CreatePathJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find(user_id)

    # Get all points ordered by timestamp
    points = user.tracked_points.order(timestamp: :asc)

    # Skip if no points
    return if points.empty?

    # Initialize variables for grouping
    current_group = []
    last_point = nil

    points.find_each do |point|
      if should_start_new_group?(last_point, point)
        # Create track from current group if it's valid
        build_track_from_points(current_group, user) if current_group.size > 1

        # Start new group
        current_group = [point]
      else
        # Add to current group
        current_group << point
      end

      last_point = point
    end

    # Don't forget to process the last group
    build_track_from_points(current_group, user) if current_group.size > 1
  end

  private

  def should_start_new_group?(last_point, current_point)
    return true if last_point.nil?

    # Calculate time and distance between points
    time_diff_minutes = (current_point.timestamp - last_point.timestamp) / 60.0
    distance_meters = calculate_distance(last_point, current_point)

    # Use the same thresholds as frontend for consistency
    time_diff_minutes > (DawarichSettings.minutes_between_tracks || 60) ||
      distance_meters > (DawarichSettings.meters_between_tracks || 500)
  end

  def calculate_distance(point1, point2)
    # Use Haversine formula to calculate distance between points
    rad_per_deg = Math::PI / 180
    earth_radius = 6_371_000 # Earth's radius in meters

    lat1_rad = point1.latitude * rad_per_deg
    lat2_rad = point2.latitude * rad_per_deg
    lon1_rad = point1.longitude * rad_per_deg
    lon2_rad = point2.longitude * rad_per_deg

    lat_diff = lat2_rad - lat1_rad
    lon_diff = lon2_rad - lon1_rad

    a = Math.sin(lat_diff / 2) * Math.sin(lat_diff / 2) +
        Math.cos(lat1_rad) * Math.cos(lat2_rad) *
        Math.sin(lon_diff / 2) * Math.sin(lon_diff / 2)
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

    earth_radius * c # Distance in meters
  end

  def build_track_from_points(points, user)
    return if points.empty?

    coordinates = points.map { |p| [p.latitude, p.longitude, p.timestamp] }

    path = Tracks::BuildPath.new(coordinates.map { |c| [c[0], c[1]] }).call

    {
      user_id: user.id,
      started_at: Time.zone.at(coordinates.first.last),
      ended_at: Time.zone.at(coordinates.last.last),
      path: path
    }
  end
end
