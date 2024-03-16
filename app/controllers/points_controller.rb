class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    start_at = params[:start_at]&.to_datetime.to_i
    end_at = params[:end_at]&.to_datetime.to_i

    @points =
      if start_at.positive? && end_at.positive?
        Point.where('timestamp >= ? AND timestamp <= ?', start_at, end_at)
      else
        Point.all
      end.order(timestamp: :asc)

    @countries_and_cities = @points.group_by(&:country).transform_values { _1.pluck(:city).uniq.compact }
    @coordinates = @points.pluck(:latitude, :longitude).map { [_1.to_f, _2.to_f] }
  end
end
