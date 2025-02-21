# frozen_string_literal: true

class Api::SlimPointSerializer
  def initialize(point)
    @point = point
  end

  def call
    {
      id:        point.id,
      latitude:  point.lat,
      longitude: point.lon,
      timestamp: point.timestamp
    }
  end

  private

  attr_reader :point
end
