# frozen_string_literal: true

class Api::V1::Owntracks::PointsController < ApplicationController
  skip_forgery_protection
  before_action :authenticate_api_key

  def create
    Owntracks::PointCreatingJob.perform_later(point_params, current_api_user.id)

    render json: {}, status: :ok
  end

  private

  def point_params
    params.permit!
  end
end
