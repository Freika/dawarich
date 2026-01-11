# frozen_string_literal: true

class Api::V1::Owntracks::PointsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create]
  before_action :validate_points_limit, only: %i[create]

  def create
    OwnTracks::PointCreator.new(point_params, current_api_user.id).call

    render json: {}, status: :ok
  end

  private

  def point_params
    params.permit!
  end
end
