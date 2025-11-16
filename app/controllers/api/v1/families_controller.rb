# frozen_string_literal: true

# This controller is kept for future family-level API endpoints
# Location-specific endpoints have been moved to Api::V1::Families::LocationsController
class Api::V1::FamiliesController < ApiController
  before_action :ensure_family_feature_enabled!
  before_action :ensure_user_in_family!

  private

  def ensure_user_in_family!
    return if current_api_user.in_family?

    render json: { error: 'User is not part of a family' }, status: :forbidden
  end
end
