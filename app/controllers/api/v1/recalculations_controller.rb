# frozen_string_literal: true

class Api::V1::RecalculationsController < ApiController
  before_action :authenticate_active_api_user!
  before_action :require_write_api!

  def create
    year = params[:year].presence&.to_i

    if year && (year < 2000 || year > Date.current.year + 1)
      return render(json: { error: I18n.t('controllers.api.v1.recalculations.invalid_year') }, status: :bad_request)
    end

    unless Users::QueueDataRecalculation.new(current_api_user, year:).call
      return render(
        json: { error: I18n.t('controllers.api.v1.recalculations.recalculation_already_in_progress_for_this_user') },
        status: :conflict
      )
    end

    render json: {
      message: I18n.t(
        'controllers.api.v1.recalculations.recalculation_queued_tracks_stats_and_digests_will_be_regenerated_in'
      )
    }, status: :accepted
  end
end
