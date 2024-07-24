# frozen_string_literal: true

class VisitDraft
  attr_accessor :start_time, :end_time, :points

  def initialize(start_time)
    @start_time = start_time
    @end_time = start_time
    @points = []
  end

  def add_point(point)
    @points << point
    @end_time = point.timestamp if point.timestamp > @end_time
  end

  def duration_in_minutes
    (end_time - start_time) / 60.0
  end

  def valid?
    @points.size > 1 && duration_in_minutes >= 10
  end
end
