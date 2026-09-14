# frozen_string_literal: true

class Api::V1::Points::PositionsController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_write_api!

  def update
    result = Points::Move.call(
      user: current_api_user,
      point_id: params[:point_id],
      latitude: point_params[:latitude],
      longitude: point_params[:longitude],
      point_revision: point_params[:revision],
      track_revision: params[:track_revision],
      history_scope: normalized_history_scope
    )

    render json: MapEdits::Serializer.call(result)
  rescue Points::Move::StaleEdit => e
    render json: MapEdits::Serializer.call(e.result).merge(error: { code: 'stale_edit' }), status: :conflict
  rescue Points::Move::InvalidCoordinates, Points::Move::InvalidHistoryScope, ActiveRecord::RecordInvalid => e
    render json: { error: { code: 'invalid_edit', message: e.message } }, status: :unprocessable_entity
  rescue Points::Move::RecalculationTimeout => e
    render json: { error: { code: 'recalculation_timeout', message: e.message } }, status: :unprocessable_entity
  end

  private

  def point_params
    params.require(:point).permit(:latitude, :longitude, :revision)
  end

  def normalized_history_scope
    scope = params.require(:history_scope).permit(:start_at, :end_at, :import_id)
    {
      start_at: parse_timestamp!(scope[:start_at]),
      end_at: parse_timestamp!(scope[:end_at]),
      import_id: scope[:import_id].presence
    }
  end

  def parse_timestamp!(value)
    raise Points::Move::InvalidHistoryScope if value.blank?
    return Integer(value) if value.to_s.match?(/\A\d+\z/)

    Time.zone.iso8601(value.to_s).to_i
  rescue ArgumentError, TypeError
    raise Points::Move::InvalidHistoryScope
  end
end
