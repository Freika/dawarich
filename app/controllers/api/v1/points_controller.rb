# frozen_string_literal: true

class Api::V1::PointsController < ApiController
  include SafeTimestampParser

  before_action :authenticate_active_api_user!, only: %i[create update destroy bulk_destroy create_transition]
  before_action :require_write_api!, only: %i[update destroy bulk_destroy create_transition]
  before_action :validate_points_limit, only: %i[create]

  def index
    start_at = params[:start_at].present? ? safe_timestamp(params[:start_at]) : nil
    end_at   = params[:end_at].present? ? safe_timestamp(params[:end_at]) : Time.zone.now.to_i
    order    = params[:order] || 'desc'

    points = if ActiveModel::Type::Boolean.new.cast(params[:anomalies_only])
               scoped_points.anomaly
             else
               scoped_points.not_anomaly
             end

    points = points
             .without_raw_data
             .where(timestamp: start_at..end_at)

    if params[:min_longitude].present? && params[:max_longitude].present? &&
       params[:min_latitude].present? && params[:max_latitude].present?
      min_lng = params[:min_longitude].to_f
      max_lng = params[:max_longitude].to_f
      min_lat = params[:min_latitude].to_f
      max_lat = params[:max_latitude].to_f

      points = points.where(
        'ST_X(lonlat::geometry) BETWEEN ? AND ? AND ST_Y(lonlat::geometry) BETWEEN ? AND ?',
        min_lng, max_lng, min_lat, max_lat
      )
    end

    points = points
             .order(timestamp: order)
             .page(params[:page])
             .per(params[:per_page] || 100)

    serialized_points = points.map { |point| point_serializer.new(point).call }

    response.set_header('X-Current-Page', points.current_page.to_s)
    response.set_header('X-Total-Pages', points.total_pages.to_s)

    # For Lite users on Cloud: include the unscoped count and scoped count
    # so the frontend can show how many points fall outside the 12-month data window.
    if !DawarichSettings.self_hosted? && current_api_user.lite?
      total_in_range = current_api_user.points
                                       .where(timestamp: start_at..end_at).count
      scoped_count = points.except(:select, :order).count
      response.set_header('X-Total-Points-In-Range', total_in_range.to_s)
      response.set_header('X-Scoped-Points', scoped_count.to_s)
    end

    render json: serialized_points
  end

  def create
    points = Points::Create.new(current_api_user, batch_params).call
    sanitized = points.map { |row| row.to_h.except('xmax') }

    render json: { data: sanitized }
  end

  def update
    point = current_api_user.points.find(params[:id])

    if point.update(lonlat: "POINT(#{point_params[:longitude]} #{point_params[:latitude]})")
      if point.track_id.present?
        Rails.logger.info(
          "[PointsController] Point #{point.id} updated, enqueuing Tracks::RecalculateJob for track #{point.track_id}"
        )
        Tracks::RecalculateJob.perform_later(point.track_id)
      end

      render json: point_serializer.new(point.reload).call
    else
      render json: { error: point.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    point = current_api_user.points.find(params[:id])
    point.destroy
    User.update_counters(current_api_user.id, points_count: -1)

    render json: { message: 'Point deleted successfully' }
  end

  def bulk_destroy
    point_ids = bulk_destroy_params[:point_ids]

    render json: { error: 'No points selected' }, status: :unprocessable_entity and return if point_ids.blank?

    deleted_count = current_api_user.points.where(id: point_ids).destroy_all.count
    User.update_counters(current_api_user.id, points_count: -deleted_count) if deleted_count.positive?

    render json: { message: 'Points were successfully destroyed', count: deleted_count }, status: :ok
  end

  TRANSITION_FUTURE_TOLERANCE = 5.minutes
  TRANSITION_PAST_HORIZON = 24.hours

  def create_transition
    event_type = params.require(:event_type)
    return head :unprocessable_entity unless %w[enter leave].include?(event_type)

    occurred_at = Time.iso8601(params.require(:occurred_at))
    # Reject implausibly future events (anti-replay / clock-skew abuse)
    return head :unprocessable_entity if occurred_at > Time.current + TRANSITION_FUTURE_TOLERANCE
    # Accept past timestamps up to TRANSITION_PAST_HORIZON (offline self-hosters can
    # queue transitions for hours before their phone reconnects)
    return head :unprocessable_entity if occurred_at < Time.current - TRANSITION_PAST_HORIZON

    area = current_api_user.areas.find_by(id: params[:area_id])
    return head :no_content unless area

    lonlat_arr = params.require(:lonlat)
    GeofenceEvents::Record.call(
      user: current_api_user,
      area: area,
      event_type: event_type.to_sym,
      source: :native_app,
      occurred_at: occurred_at,
      lonlat: "POINT(#{lonlat_arr[0]} #{lonlat_arr[1]})",
      accuracy_m: params[:accuracy_m],
      device_id: params[:device_id],
      metadata: params[:metadata] || {}
    )

    head :created
  rescue ArgumentError, ActionController::ParameterMissing
    head :unprocessable_entity
  end

  private

  def point_params
    params.require(:point).permit(:latitude, :longitude)
  end

  def batch_params
    params.permit(locations: [:type, { geometry: {}, properties: {} }], batch: {})
  end

  def bulk_destroy_params
    params.permit(point_ids: [])
  end

  def point_serializer
    params[:slim] == 'true' ? Api::SlimPointSerializer : Api::PointSerializer
  end
end
