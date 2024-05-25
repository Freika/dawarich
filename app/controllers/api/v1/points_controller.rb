# frozen_string_literal: true

# TODO: Deprecate in 1.0

class Api::V1::PointsController < ApplicationController
  skip_forgery_protection

  def create
    Rails.logger.info 'This endpoint will be deprecated in 1.0. Use /api/v1/owntracks/points instead'
    Owntracks::PointCreatingJob.perform_later(point_params)

    render json: {}, status: :ok
  end

  private

  def point_params
    params.permit!
  end
end
