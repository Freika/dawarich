# frozen_string_literal: true

class Tracks::BuildPath
  def initialize(coordinates)
    @coordinates = coordinates
  end

  def call
    factory.line_string(
      coordinates.map { |point| factory.point(point[1].to_f.round(5), point[0].to_f.round(5)) }
    )
  end

  private

  attr_reader :coordinates

  def factory
    @factory ||= RGeo::Geographic.spherical_factory(srid: 3857)
  end
end
