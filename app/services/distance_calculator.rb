# frozen_string_literal: true

class DistanceCalculator
  def initialize(point1, point2)
    @point1 = point1
    @point2 = point2
  end

  def call
    Geocoder::Calculations.distance_between(
      point1.to_coordinates, point2.to_coordinates, units: ::DISTANCE_UNIT
    )
  end

  private

  attr_reader :point1, :point2
end
