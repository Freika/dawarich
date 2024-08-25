# frozen_string_literal: true

class Api::V1::Owntracks::PointsController < ApiController
  def create
    Owntracks::PointCreatingJob.perform_later(point_params, current_api_user.id)

    render json: {}, status: :ok
  end

  private

  def point_params
    params.permit!
  end
end
