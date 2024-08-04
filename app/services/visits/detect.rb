require 'geokit'

class Visits::Detect
  def initialize
    a = 5.days.ago.beginning_of_month
    b = 5.days.ago.end_of_month
    @points = Point.order(timestamp: :asc).where(timestamp: a..b)
  end

  def call
    # Group points by day
    points_by_day = @points.group_by { |point| point_date(point) }

    # Iterate through each day's points
    points_by_day.each do |day, day_points|
      # Sort points by timestamp
      day_points.sort_by! { |point| point.timestamp }

      # Call the method for each day's points
      grouped_points = group_points_by_radius(day_points)

      # Print the grouped points for the day
      puts "Day: #{day}"
      grouped_points.each_with_index do |group, index|
        puts "Group #{index + 1}:"
        group.each do |point|
          puts point
        end
      end
    end
  end

  private

  # Method to convert timestamp to date
  def point_date(point)
    Time.zone.at(point.timestamp).to_date
  end

  # Method to check if two points are within a certain radius (in meters)
  def within_radius?(point1, point2, radius)
    loc1 = Geokit::LatLng.new(point1.latitude, point1.longitude)
    loc2 = Geokit::LatLng.new(point2.latitude, point2.longitude)
    loc1.distance_to(loc2, units: :kms) * 1000 <= radius
  end

  # Method to group points by increasing radius
  def group_points_by_radius(day_points, initial_radius = 30, max_radius = 100, step = 10)
    grouped = []
    remaining_points = day_points.dup

    while remaining_points.any?
      point = remaining_points.shift
      group = [point]
      radius = initial_radius

      while radius <= max_radius
        remaining_points.each do |next_point|
          group << next_point if within_radius?(point, next_point, radius)
        end

        if group.size > 1
          remaining_points -= group
          grouped << group
          break
        else
          radius += step
        end
      end
    end

    grouped
  end
end

# Execute the detection
# Visits::Detect.new.call
