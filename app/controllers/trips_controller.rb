# frozen_string_literal: true

class TripsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_trip, only: %i[show edit update destroy]

  def index
    @trips = current_user.trips
  end

  def show; end

  def new
    @trip = Trip.new
  end

  def edit; end

  def create
    @trip = current_user.trips.build(trip_params)

    if @trip.save
      redirect_to @trip, notice: 'Trip was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @trip.update(trip_params)
      redirect_to @trip, notice: 'Trip was successfully updated.', status: :see_other
    else
      render :edit, status: :unprocessable_entity
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

  def trip_params
    params.require(:trip).permit(:name, :started_at, :ended_at, :notes)
  end
end
