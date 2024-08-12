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
        latitude: center_point.latitude,
        longitude: center_point.longitude,
        radius: calculate_radius(center_point, group),
        points: group,
        duration: (group.last.timestamp - group.first.timestamp).to_i / 60
      }
    end
  end
end
