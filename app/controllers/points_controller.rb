class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = Point.all.order(timestamp: :asc)

    @coordinates = @points.pluck(:latitude, :longitude).map { [_1.to_f, _2.to_f] }
  end
end
