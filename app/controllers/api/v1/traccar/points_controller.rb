# frozen_string_literal: true

class Api::V1::Traccar::PointsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create]
  before_action :validate_points_limit, only: %i[create]

  def create
    Traccar::PointCreator.new(point_params, current_api_user.id).call

    render json: [], status: :ok
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid, ArgumentError => e
    Sentry.capture_exception(e)

    render json: { error: 'Point creation failed' }, status: :internal_server_error
  end

  private

  def point_params
    params.permit(
      :device_id,
      location: %i[timestamp latitude longitude accuracy speed heading altitude
                   is_moving odometer event],
      battery: %i[level is_charging],
      activity: %i[type]
    )
  end
end
