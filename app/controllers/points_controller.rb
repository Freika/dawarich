class PointsController < ApplicationController
  def index
    @points = Point.all

    @coordinates = @points.as_json(only: [:latitude, :longitude])
  end
end
