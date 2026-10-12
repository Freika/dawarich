# frozen_string_literal: true

class Api::V1::Families::BaseController < ApiController
  before_action :ensure_family_feature_available!
  before_action :ensure_user_in_family!

  private

  def ensure_user_in_family!
    return if current_api_user&.in_family?

    render json: { error: I18n.t('controllers.api.v1.families.locations.user_is_not_part_of_a_family') },
           status: :not_found
  end
end
