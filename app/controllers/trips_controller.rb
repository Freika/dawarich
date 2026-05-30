# frozen_string_literal: true

class TripsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[new create recalculate]
  before_action :set_trip, only: %i[show edit update destroy recalculate export]
  before_action :set_coordinates, only: %i[show edit]

  def index
    @trips = current_user.trips.order(started_at: :desc).page(params[:page]).per(6)
  end

  def show
    @photo_previews = @trip.photo_previews
    @photo_sources = @trip.photo_sources

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
      @trip.adopt!
      redirect_to @trip, notice: 'Trip was successfully updated.', status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @trip.destroy!
    redirect_to trips_url, notice: 'Trip was successfully destroyed.', status: :see_other
  end

  def recalculate
    affected = current_user.trips
                           .where(id: @trip.id)
                           .where('last_recalculated_at IS NULL OR last_recalculated_at < ?', Trip::RECALCULATE_COOLDOWN.ago)
                           .update_all(last_recalculated_at: Time.current)

    if affected.zero?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:notice,
                                            'Already recalculating — this page will update when it\'s done.')
        end
        format.html do
          redirect_to trip_path(@trip),
                      notice: 'Already recalculating — this page will update when it\'s done.'
        end
      end
      return
    end

    @trip.reload
    Trips::CalculateAllJob.perform_later(@trip.id, current_user.safe_settings.distance_unit)
    Rails.logger.info("trip_recalculate trip_id=#{@trip.id} user_id=#{current_user.id}")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('trip_recalculate_frame',
                               partial: 'trips/recalculate_button',
                               locals: { trip: @trip }),
          stream_flash(:notice, 'Recalculating — the page will update automatically when it\'s ready.')
        ]
      end
      format.html do
        redirect_to trip_path(@trip),
                    notice: 'Recalculating — the page will update automatically when it\'s ready.'
      end
    end
  end

  EXPORTABLE_FORMATS = %w[gpx json].freeze

  def export
    file_format = params[:file_format].to_s

    unless EXPORTABLE_FORMATS.include?(file_format)
      redirect_to trip_path(@trip),
                  alert: 'Unsupported export format. Choose GPX or GeoJSON.',
                  status: :unprocessable_content
      return
    end

    tz = current_user.safe_settings.timezone.presence || 'UTC'
    start_date = @trip.started_at.in_time_zone(tz).to_date
    export_name = "trip_#{@trip.name.to_s.parameterize.presence || @trip.id}_#{start_date}.#{file_format}"

    current_user.exports.create!(
      name: export_name,
      status: :created,
      file_format: file_format,
      file_type: :points,
      start_at: @trip.started_at,
      end_at: @trip.ended_at
    )

    redirect_to exports_url,
                notice: "Trip export initiated. Check the Exports page when it's ready."
  rescue StandardError => e
    ExceptionReporter.call(e)
    redirect_to trip_path(@trip),
                alert: 'Export failed to initiate. Please try again.',
                status: :unprocessable_content
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
    params.require(:trip).permit(:name, :started_at, :ended_at, :notes)
  end
end
