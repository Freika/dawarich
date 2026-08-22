# frozen_string_literal: true

class Api::V1::Families::SharingController < Api::V1::Families::BaseController
  def update
    params.require(:enabled)

    result = Families::UpdateLocationSharing.new(
      user: current_api_user,
      enabled: params[:enabled],
      duration: params[:duration],
      share_history: params[:share_history],
      history_window: params[:history_window]
    ).call

    render json: result.payload, status: result.status
  rescue ActionController::ParameterMissing => e
    error = I18n.t('controllers.api.v1.families.sharing.missing_required_parameter_param', parameter: e.param)
    render json: { error: error }, status: :bad_request
  end
end
