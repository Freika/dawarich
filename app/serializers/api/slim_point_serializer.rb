# frozen_string_literal: true

class Api::SlimPointSerializer
  def initialize(point)
    @point = point
  end

  def call
    {
      id:        point.id,
      latitude:  point.lat.to_s,
      longitude: point.lon.to_s,
      timestamp: point.timestamp
    }
  end

  private

  attr_reader :point
end
