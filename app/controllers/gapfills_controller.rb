# frozen_string_literal: true

class GapfillsController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :require_pro!
  before_action :require_gapfill_enabled!
  before_action :load_points

  after_action :verify_authorized

  def preview
    authorize :gapfill, :preview?

    coordinates = router.route(
      from: { lon: @start_point.lon, lat: @start_point.lat },
      to: { lon: @end_point.lon, lat: @end_point.lat },
      mode: params[:mode],
      alternative: params[:alternative] || 0
    )
    render json: { coordinates: coordinates }
  rescue Gapfill::Router::RoutingError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    authorize :gapfill, :create?

    coordinates = router.route(
      from: { lon: @start_point.lon, lat: @start_point.lat },
      to: { lon: @end_point.lon, lat: @end_point.lat },
      mode: params[:mode],
      alternative: params[:alternative] || 0
    )

    new_points = Gapfill::PointGenerator.new(
      coordinates: coordinates,
      start_point: @start_point,
      end_point: @end_point,
      user: current_user
    ).build_points

    geojson = {
      type: 'FeatureCollection',
      features: [{
        type: 'Feature',
        geometry: { type: 'LineString', coordinates: coordinates },
        properties: {
          mode: params[:mode],
          start_point_id: @start_point.id,
          end_point_id: @end_point.id
        }
      }]
    }.to_json

    Point.transaction do
      import = current_user.imports.create!(
        name: gapfill_import_name,
        source: :geojson,
        status: :completed,
        skip_background_processing: true
      )

      import.file.attach(
        io: StringIO.new(geojson),
        filename: "gapfill_#{import.id}.geojson",
        content_type: 'application/json'
      )

      new_points.each do |point|
        point.import = import
        point.save!
      end

      import.update_columns(points_count: new_points.size, processed: new_points.size)
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: stream_flash(:notice, "Added #{new_points.size} inferred points")
      end
      format.html { redirect_to map_v2_path, notice: "Added #{new_points.size} inferred points", status: :see_other }
    end
  rescue Gapfill::Router::RoutingError => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:error, e.message) }
      format.html { redirect_to map_v2_path, alert: e.message, status: :see_other }
    end
  end

  private

  def router
    @router ||= Gapfill::Router.new
  end

  def load_points
    @start_point = current_user.points.find(params[:start_point_id])
    @end_point = current_user.points.find(params[:end_point_id])
  end

  def gapfill_import_name
    mode = params[:mode].presence || 'Route'
    time = Time.zone.at(@start_point.timestamp).strftime('%Y-%m-%d %H:%M')
    "Gap-fill (#{mode}, #{time})"
  end

  def require_gapfill_enabled!
    return if DawarichSettings.gapfill_enabled?

    respond_to do |format|
      format.html { redirect_to map_v2_path, alert: 'Gap-fill requires BROUTER_URL to be configured.', status: :see_other }
      format.json { render json: { error: 'Gap-fill requires BROUTER_URL to be configured.' }, status: :forbidden }
      format.turbo_stream do
        render turbo_stream: stream_flash(:error, 'Gap-fill requires BROUTER_URL to be configured.')
      end
    end
  end
end
