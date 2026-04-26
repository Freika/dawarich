# frozen_string_literal: true

class Api::V1::RecalculationsController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_write_api!

  def create
    year = params[:year].presence&.to_i

    Users::RecalculateDataJob.perform_later(current_api_user.id, year: year)

    render json: {
      message: 'Recalculation queued. Tracks, stats, and digests will be regenerated in the background.'
    }, status: :accepted
  end
end
