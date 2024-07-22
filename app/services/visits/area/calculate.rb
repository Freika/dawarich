# frozen_string_literal: true

class Visits::Area::Calculate
  attr_accessor :point

  def initialize(point)
    @point = point
  end

  def call
    return unless point.city && point.country

    #   After a reverse geocoding process done for a point, check if there are any areas in the same country+city.
    # If there are, check if the point coordinates are within the area's boundaries.
    #   If they are, find or create a Visit: Name of Area + point.id (visit has many points and belongs to area, point optionally belong to a visit)
    #

    areas = Area.where(city: point.city, country: point.country)
  end

  private

  def days
    # 1. Getting all the points within the area
    points = Point.near([area.latitude, area.longitude], area.radius).order(:timestamp)

    # 2. Grouping the points by date
    points.group_by { |point| Time.at(point.timestamp).to_date }
  end

  def visits
    # 3. Within each day, group points by hour. If difference between two groups is less than 1 hour, they are considered to be part of the same visit.

    days.map do |day, points|
      points.group_by { |point| Time.at(point.timestamp).strftime('%Y-%m-%d %H') }
    end

    # 4. If a visit has more than 1 point, it is considered a visit.

end
