# frozen_string_literal: true

class TripsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[new create]
  before_action :set_trip, only: %i[show edit update destroy]
  before_action :set_coordinates, only: %i[show edit]

  def index
    @trips = current_user.trips.order(started_at: :desc).page(params[:page]).per(6)
  end

  def show
    @photo_previews = @trip.photo_previews
    @photo_sources = @trip.photo_sources
    @day_notes = @trip.notes.index_by(&:date)
    @day_stats = compute_day_stats

    return unless @trip.path.blank? || @trip.distance.blank? || @trip.visited_countries.blank?

    Trips::CalculateAllJob.perform_later(@trip.id, current_user.safe_settings.distance_unit)
  end

  def new
    @trip = Trip.new
    @coordinates = []
  end

  def edit; end

  def create
    @trip = current_user.trips.build(trip_params)

    if @trip.save
      redirect_to @trip, notice: 'Trip was successfully created. Data is being calculated in the background.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @trip.update(trip_params)
      redirect_to @trip, notice: 'Trip was successfully updated.', status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @trip.destroy!
    redirect_to trips_url, notice: 'Trip was successfully destroyed.', status: :see_other
  end

  private

  def set_trip
    @trip = current_user.trips.find(params[:id])
  end

  def set_coordinates
    @coordinates = @trip.points.pluck(
      :latitude, :longitude, :battery, :altitude, :timestamp, :velocity, :id,
      :country
    ).map { [_1.to_f, _2.to_f, _3.to_s, _4.to_s, _5.to_s, _6.to_s, _7.to_s, _8.to_s] }
  end

  def trip_params
    params.require(:trip).permit(:name, :started_at, :ended_at, :description)
  end

  def compute_day_stats
    tz = current_user.timezone
    points_data = @trip.points.order(:timestamp)
                       .pluck(Arel.sql('ST_Y(lonlat::geometry)'), Arel.sql('ST_X(lonlat::geometry)'), :timestamp)
    return {} if points_data.empty?

    points_data.group_by { |_, _, ts| Time.at(ts).in_time_zone(tz).to_date }.transform_values do |pts|
      first_time = Time.at(pts.first[2]).in_time_zone(tz)
      last_time  = Time.at(pts.last[2]).in_time_zone(tz)

      distance_km = 0.0
      pts.each_cons(2) do |(lat1, lon1, _), (lat2, lon2, _)|
        distance_km += haversine_km(lat1.to_f, lon1.to_f, lat2.to_f, lon2.to_f)
      end

      { first_time: first_time, last_time: last_time, distance_km: distance_km }
    end
  end

  def haversine_km(lat1, lon1, lat2, lon2)
    r = 6371.0
    dlat = (lat2 - lat1) * Math::PI / 180
    dlon = (lon2 - lon1) * Math::PI / 180
    a = Math.sin(dlat / 2)**2 +
        Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(dlon / 2)**2
    r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  end
end
