# frozen_string_literal: true

class Visits::GroupPoints
  INITIAL_RADIUS = 30 # meters
  MAX_RADIUS = 100 # meters
  RADIUS_STEP = 10 # meters
  MIN_VISIT_DURATION = 3 * 60 # 3 minutes in seconds

  attr_reader :day_points, :initial_radius, :max_radius, :step

  def initialize(day_points, initial_radius = INITIAL_RADIUS, max_radius = MAX_RADIUS, step = RADIUS_STEP)
    @day_points = day_points
    @initial_radius = initial_radius
    @max_radius = max_radius
    @step = step
  end

  def group_points_by_radius
    grouped = []
    remaining_points = day_points.dup

    while remaining_points.any?
      point = remaining_points.shift
      radius = initial_radius

      while radius <= max_radius
        new_group = [point]

        remaining_points.each do |next_point|
          break unless within_radius?(new_group.first, next_point, radius)

          new_group << next_point
        end

        if new_group.size > 1
          group_duration = new_group.last.timestamp - new_group.first.timestamp

          if group_duration >= MIN_VISIT_DURATION
            remaining_points -= new_group
            grouped << new_group
          end

          break
        else
          radius += step
        end
      end
    end

    grouped
  end

  private

  def within_radius?(point1, point2, radius)
    point1.distance_to(point2) * 1000 <= radius
  end
end
