# frozen_string_literal: true

class Visits::Suggest
  def initialize(start_at: nil, end_at: nil)
    start_at ||= Date.new(2024, 7, 15).to_datetime.beginning_of_day.to_i
    end_at ||= Date.new(2024, 7, 19).to_datetime.end_of_day.to_i
    @points = Point.order(timestamp: :asc).where(timestamp: start_at..end_at)
  end

  def call
    points_by_day = @points.group_by { |point| point_date(point) }

    result = {}

    points_by_day.each do |day, day_points|
      day_points.sort_by!(&:timestamp)

      grouped_points = Visits::GroupPoints.new(day_points).group_points_by_radius
      day_result     = prepare_day_result(grouped_points)
      result[day]    = day_result
    end

    result
  end

  private

  def point_date(point) = Time.zone.at(point.timestamp).to_date.to_s

  def calculate_radius(center_point, group)
    max_distance = group.map { |point| center_point.distance_to(point) }.max

    (max_distance / 10.0).ceil * 10
  end

  def prepare_day_result(grouped_points)
    result = {}

    grouped_points.each do |group|
      center_point = group.first
      radius = calculate_radius(center_point, group)
      key = "#{center_point.latitude},#{center_point.longitude},#{radius}m,#{group.size}"
      result[key] = group.count
    end

    result
  end
end
