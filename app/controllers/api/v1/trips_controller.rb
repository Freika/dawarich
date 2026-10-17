# frozen_string_literal: true

class Api::V1::TripsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create]
  before_action :set_trip, only: %i[show update destroy]

  def index
    start_at = parse_time_param(:start_at)
    end_at = parse_time_param(:end_at)
    if [start_at, end_at].include?(false)
      return render json: { error: 'Invalid date format' }, status: :unprocessable_content
    end

    trips = current_api_user.trips.with_rich_text_description.order(started_at: :desc)
    trips = trips.where('ended_at >= ?', start_at) if start_at
    trips = trips.where('started_at <= ?', end_at) if end_at

    # Optional pagination (returns all trips if no page param, like visits)
    if params[:page].present?
      per_page = (params[:per_page].presence || 25).to_i.clamp(1, 100)
      trips = trips.page(params[:page]).per(per_page)

      response.set_header('X-Current-Page', trips.current_page.to_s)
      response.set_header('X-Total-Pages', trips.total_pages.to_s)
      response.set_header('X-Total-Count', trips.total_count.to_s)
    end

    render json: trips.map { Api::TripSerializer.new(_1).call }, status: :ok
  end

  def show
    render json: Api::TripSerializer.new(@trip, include_path: true).call, status: :ok
  end

  def create
    trip = current_api_user.trips.build(trip_params)

    if trip.save
      render json: Api::TripSerializer.new(trip).call, status: :created
    else
      render json: { errors: trip.errors.full_messages }, status: :unprocessable_content
    end
  end

  def update
    if @trip.update(trip_params)
      @trip.adopt!
      render json: Api::TripSerializer.new(@trip).call, status: :ok
    else
      render json: { errors: @trip.errors.full_messages }, status: :unprocessable_content
    end
  end

  def destroy
    @trip.destroy!

    render json: { message: I18n.t('controllers.api.v1.trips.trip_was_successfully_deleted') }, status: :ok
  end

  private

  def set_trip
    @trip = current_api_user.trips.find(params[:id])
  end

  def trip_params
    params.require(:trip).permit(:name, :started_at, :ended_at, :description)
  end

  # nil when the param is blank, false when it can't be parsed.
  def parse_time_param(key)
    return if params[key].blank?

    Time.zone.parse(params[key].to_s) || false
  rescue ArgumentError
    false
  end
end
