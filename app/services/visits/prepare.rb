# frozen_string_literal: true

class Visits::Prepare
  attr_reader :points

  def initialize(points)
    @points = points
  end

  def call
    points_by_day = points.group_by { |point| point_date(point) }

    points_by_day.map do |day, day_points|
      day_points.sort_by!(&:timestamp)

      grouped_points = Visits::GroupPoints.new(day_points).group_points_by_radius
      day_result     = prepare_day_result(grouped_points)

      # Iterate through the day_result, check if there are any points outside
      # of visits that are between two consecutive visits. If there are none,
      # merge the visits.

      day_result.each_cons(2) do |visit1, visit2|
        next if visit1[:points].last == visit2[:points].first

        points_between_visits = day_points.select do |point|
          point.timestamp > visit1[:points].last.timestamp &&
            point.timestamp < visit2[:points].first.timestamp
        end

        if points_between_visits.any?
          # If there are points between the visits, we need to check if they are close enough to the visits to be considered part of them.

          points_between_visits.each do |point|
            next unless visit1[:points].last.distance_to(point) < visit1[:radius] ||
                        visit2[:points].first.distance_to(point) < visit2[:radius] ||
                        (point.timestamp - visit1[:points].last.timestamp).to_i < 600

            visit1[:points] << point
          end
        end

        visit1[:points] += visit2[:points]
        visit1[:duration] = (visit1[:points].last.timestamp - visit1[:points].first.timestamp).to_i / 60
        visit1[:ended_at] = Time.zone.at(visit1[:points].last.timestamp)
        day_result.delete(visit2)
      end

      next if day_result.blank?

      { date: day, visits: day_result }
    end.compact
  end

  private

  def point_date(point) = Time.zone.at(point.timestamp).to_date.to_s

  def calculate_radius(center_point, group)
    max_distance = group.map { |point| center_point.distance_to(point) }.max

    (max_distance / 10.0).ceil * 10
  end

  def prepare_day_result(grouped_points)
    grouped_points.map do |group|
      center_point = group.first

      {
        lonlat: "POINT(#{center_point.lon} #{center_point.lat})",
        radius: calculate_radius(center_point, group),
        points: group,
        duration: (group.last.timestamp - group.first.timestamp).to_i / 60,
        started_at: Time.zone.at(group.first.timestamp).to_s,
        ended_at: Time.zone.at(group.last.timestamp).to_s
      }
    end
  end
end
