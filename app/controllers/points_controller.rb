class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    start_at = params[:start_at].to_datetime.to_i
    end_at = params[:end_at].to_datetime.to_i

    @points = Point.all.order(timestamp: :asc)
    @points = Point.all.where('timestamp >= ? AND timestamp <= ?', start_at, end_at).order(timestamp: :asc) if start_at && end_at

    @coordinates = @points.pluck(:latitude, :longitude).map { [_1.to_f, _2.to_f] }
  end
end
