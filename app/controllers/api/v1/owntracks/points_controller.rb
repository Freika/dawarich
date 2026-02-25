# frozen_string_literal: true

class Api::V1::Owntracks::PointsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create]
  before_action :validate_points_limit, only: %i[create]

  def create
    OwnTracks::PointCreator.new(point_params, current_api_user.id).call

    render json: [], status: :ok
  rescue StandardError => e
    Sentry.capture_exception(e) if defined?(Sentry)

    render json: { error: 'Point creation failed' }, status: :internal_server_error
  end

  private

  def point_params
    params.permit!
  end
end
