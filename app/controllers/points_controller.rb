class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = Point.all

    @coordinates = @points.as_json(only: [:latitude, :longitude])
  end
end
