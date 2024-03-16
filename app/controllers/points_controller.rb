class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = Point.where('timestamp >= ? AND timestamp <= ?', start_at, end_at).order(timestamp: :asc)

    @countries_and_cities = @points.group_by(&:country).transform_values { _1.pluck(:city).uniq.compact }
    @coordinates = @points.pluck(:latitude, :longitude).map { [_1.to_f, _2.to_f] }
  end

  def start_at
    return 1.month.ago.beginning_of_day.to_i if params[:start_at].nil?

    params[:start_at].to_datetime.to_i
  end

  def end_at
    return Date.today.end_of_day.to_i if params[:end_at].nil?

    params[:end_at].to_datetime.to_i
  end
end
