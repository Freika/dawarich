class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = Point.where('timestamp >= ? AND timestamp <= ?', start_at, end_at).order(timestamp: :asc)

    @countries_and_cities = CountriesAndCities.new(@points).call
    @coordinates = @points.pluck(:latitude, :longitude).map { [_1.to_f, _2.to_f] }
    @distance = distance
    @start_at = Time.at(start_at)
    @end_at = Time.at(end_at)
  end

  private

  def start_at
    return 1.month.ago.beginning_of_day.to_i if params[:start_at].nil?

    params[:start_at].to_datetime.to_i
  end

  def end_at
    return Date.today.end_of_day.to_i if params[:end_at].nil?

    params[:end_at].to_datetime.to_i
  end

  def distance
    @distance ||= 0

    @coordinates.each_cons(2) do
      @distance += Geocoder::Calculations.distance_between(_1[0], _1[1], units: :km)
    end

    @distance.round(1)
  end
end
