# frozen_string_literal: true

class Api::V1::RecalculationsController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_write_api!

  PENDING_KEY_TTL = 30.minutes

  def create
    year = params[:year].presence&.to_i

    if year && (year < 2000 || year > Date.current.year + 1)
      return render(json: { error: I18n.t('controllers.api.v1.recalculations.invalid_year') }, status: :bad_request)
    end

    pending_key = "recalculation_pending:#{current_api_user.id}"
    if Rails.cache.read(pending_key)
      return render(
        json: { error: I18n.t('controllers.api.v1.recalculations.recalculation_already_in_progress_for_this_user') },
        status: :conflict
      )
    end

    Rails.cache.write(pending_key, true, expires_in: PENDING_KEY_TTL)
    Users::RecalculateDataJob.perform_later(current_api_user.id, year: year)

    render json: {
      message: I18n.t(
        'controllers.api.v1.recalculations.recalculation_queued_tracks_stats_and_digests_will_be_regenerated_in'
      )
    }, status: :accepted
  end
end
