# frozen_string_literal: true

class Api::V1::RecalculationsController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_write_api!

  PENDING_KEY_TTL = 30.minutes

  def create
    year = params[:year].presence&.to_i

    if year && (year < 2000 || year > Date.current.year + 1)
      return render(json: { error: 'Invalid year' }, status: :bad_request)
    end

    pending_key = "recalculation_pending:#{current_api_user.id}"
    if Rails.cache.read(pending_key)
      return render(
        json: { error: 'Recalculation already in progress for this user.' },
        status: :conflict
      )
    end

    Rails.cache.write(pending_key, true, expires_in: PENDING_KEY_TTL)
    Users::RecalculateDataJob.perform_later(current_api_user.id, year: year)

    render json: {
      message: 'Recalculation queued. Tracks, stats, and digests will be regenerated in the background.'
    }, status: :accepted
  end
end
