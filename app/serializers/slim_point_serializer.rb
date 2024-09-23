# frozen_string_literal: true

class SlimPointSerializer
  def initialize(point)
    @point = point
  end

  def call
    {
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: point.timestamp
    }
  end

  private

  attr_reader :point
end
