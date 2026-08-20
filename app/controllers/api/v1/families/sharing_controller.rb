# frozen_string_literal: true

class Api::V1::Families::SharingController < ApiController
  before_action :ensure_family_feature_available!
  before_action :ensure_user_in_family!

  def update
    result = Families::UpdateLocationSharing.new(
      user: current_api_user,
      enabled: params[:enabled],
      duration: params[:duration],
      share_history: params[:share_history],
      history_window: params[:history_window]
    ).call

    render json: result.payload, status: result.status
  end

  private

  def ensure_user_in_family!
    return if current_api_user&.in_family?

    render json: { error: I18n.t('controllers.api.v1.families.locations.user_is_not_part_of_a_family') },
           status: :not_found
  end
end
