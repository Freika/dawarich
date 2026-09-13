# frozen_string_literal: true

class TripsController < ApplicationController
  include FlashStreamable
  include VideoStudioContext

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[new create recalculate]
  before_action :set_trip, only: %i[show edit update destroy recalculate export]

  def index
    @trips = current_user.trips.order(started_at: :desc).page(params[:page]).per(6)
  end

  def show
    @photo_sources = @trip.photo_sources
    @distance_unit = current_user.safe_settings.distance_unit
    @timezone = current_user.timezone_iana
    @photos_by_day = @trip.photos_by_day(@timezone)
    @day_notes = @trip.notes.index_by(&:date)
    @day_stats = compute_day_stats
    load_video_studio_context

    return unless @trip.path.blank? || @trip.distance.blank? || @trip.visited_countries.blank?

    Trips::CalculateAllJob.perform_later(@trip.id, @distance_unit)
  end

  def new
    @trip = Trip.new
  end

  def edit; end

  def create
    @trip = current_user.trips.build(trip_params)

    if @trip.save
      redirect_to @trip,
                  notice: I18n.t('controllers.trips.trip_was_successfully_created_data_is_being_calculated_in_the')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @trip.update(trip_params)
      @trip.adopt!
      redirect_to @trip, notice: I18n.t('controllers.trips.trip_was_successfully_updated'), status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @trip.destroy!
    redirect_to trips_url, notice: I18n.t('controllers.trips.trip_was_successfully_destroyed'), status: :see_other
  end

  def recalculate
    affected = current_user.trips
                           .where(id: @trip.id)
                           .where('last_recalculated_at IS NULL OR last_recalculated_at < ?', Trip::RECALCULATE_COOLDOWN.ago)
                           .update_all(last_recalculated_at: Time.current)

    if affected.zero?
      notice = I18n.t('controllers.trips.already_recalculating_this_page_will_update_when_it_s_done')
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: stream_flash(:notice, notice)
        end
        format.html do
          redirect_to trip_path(@trip),
                      notice: notice
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
          stream_flash(
            :notice,
            I18n.t('controllers.trips.recalculating_the_page_will_update_automatically_when_it_s_ready')
          )
        ]
      end
      format.html do
        redirect_to trip_path(@trip),
                    notice: I18n.t('controllers.trips.recalculating_the_page_will_update_automatically_when_it_s_ready')
      end
    end
  end

  EXPORTABLE_FORMATS = %w[gpx json].freeze

  def export
    file_format = params[:file_format].to_s

    unless EXPORTABLE_FORMATS.include?(file_format)
      redirect_to trip_path(@trip),
                  alert: I18n.t('controllers.trips.unsupported_export_format_choose_gpx_or_geojson'),
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
                notice: I18n.t('controllers.trips.trip_export_initiated_check_the_exports_page_when_it_s')
  rescue StandardError => e
    ExceptionReporter.call(e)
    redirect_to trip_path(@trip),
                alert: I18n.t('controllers.trips.export_failed_to_initiate_please_try_again'),
                status: :unprocessable_content
  end

  private

  def set_trip
    @trip = current_user.trips.find(params[:id])
  end

  def trip_params
    params.require(:trip).permit(:name, :started_at, :ended_at, :description)
  end

  def compute_day_stats
    max_points_updated = @trip.points.maximum(:updated_at).to_i
    cache_key = "trip_day_stats/v2/#{@trip.id}/#{@trip.updated_at.to_i}/#{max_points_updated}/#{@timezone}"

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      tz_quoted = ActiveRecord::Base.connection.quote(@timezone)
      day_expr  = "(to_timestamp(timestamp) AT TIME ZONE #{tz_quoted})::date"

      rows = @trip.points.reorder(nil).group(Arel.sql(day_expr)).pluck(
        Arel.sql(day_expr),
        Arel.sql('MIN(timestamp)'),
        Arel.sql('MAX(timestamp)'),
        Arel.sql('COALESCE(ST_Length(ST_MakeLine(lonlat::geometry ORDER BY timestamp)::geography), 0)')
      )

      rows.each_with_object({}) do |(day, first_ts, last_ts, distance_m), acc|
        acc[day] = {
          first_time: Time.at(first_ts).in_time_zone(@timezone),
          last_time:  Time.at(last_ts).in_time_zone(@timezone),
          distance_m: distance_m.to_f
        }
      end
    end
  end
end
