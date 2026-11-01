# frozen_string_literal: true

class Api::V1::Points::MotionsController < ApiController
  before_action :authenticate_active_api_user!

  def update
    render json: Points::UpdateMotion.new(current_api_user, params[:updates]).call
  rescue Points::UpdateMotion::InvalidUpdates => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
