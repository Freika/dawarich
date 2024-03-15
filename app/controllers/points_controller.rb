class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = current_user.points

    @coordinates = @points.as_json(only: [:latitude, :longitude])
  end
end
