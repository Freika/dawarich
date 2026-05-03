# frozen_string_literal: true

class Api::V1::PointsController < ApiController
  include SafeTimestampParser

  before_action :authenticate_active_api_user!, only: %i[create update destroy bulk_destroy reapply_anomaly_filter]
  before_action :require_write_api!, only: %i[update destroy bulk_destroy reapply_anomaly_filter]
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
      bbox = parse_bbox(params)
      return render(json: { error: 'Invalid bounding box' }, status: :bad_request) unless bbox

      points = points.where(
        'ST_X(lonlat::geometry) BETWEEN ? AND ? AND ST_Y(lonlat::geometry) BETWEEN ? AND ?',
        bbox[:min_lng], bbox[:max_lng], bbox[:min_lat], bbox[:max_lat]
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

  def reapply_anomaly_filter
    pending_key = "anomaly_backfill_pending:#{current_api_user.id}"
    if Rails.cache.read(pending_key)
      return render(
        json: { error: 'Anomaly re-evaluation already in progress.' },
        status: :conflict
      )
    end

    Rails.cache.write(pending_key, true, expires_in: 30.minutes)
    Points::AnomalyBackfillUserJob.perform_later(current_api_user.id, reset: true)

    render json: {
      message: 'Re-evaluation queued. Existing anomaly flags will be cleared and recomputed.'
    }, status: :accepted
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

  # Validate and parse a bbox from request params. Rejects non-finite values
  # (NaN/Infinity from `to_f` on garbage strings), inverted ranges, and
  # out-of-range geographic coordinates. Returns nil on invalid input.
  def parse_bbox(params)
    min_lng = safe_float(params[:min_longitude])
    max_lng = safe_float(params[:max_longitude])
    min_lat = safe_float(params[:min_latitude])
    max_lat = safe_float(params[:max_latitude])

    return nil if [min_lng, max_lng, min_lat, max_lat].any? { |v| v.nil? || !v.finite? }
    return nil if min_lng > max_lng || min_lat > max_lat
    return nil unless min_lng.between?(-180, 180) && max_lng.between?(-180, 180)
    return nil unless min_lat.between?(-90, 90) && max_lat.between?(-90, 90)

    { min_lng: min_lng, max_lng: max_lng, min_lat: min_lat, max_lat: max_lat }
  end

  def safe_float(value)
    Float(value)
  rescue ArgumentError, TypeError
    nil
  end
end
