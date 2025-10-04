# frozen_string_literal: true

class Api::V1::FamiliesController < ApiController
  before_action :ensure_family_feature_enabled!
  before_action :ensure_user_in_family!

  def locations
    family_locations = Families::Locations.new(current_api_user).call

    render json: {
      locations: family_locations,
      updated_at: Time.current.iso8601,
      sharing_enabled: current_api_user.family_sharing_enabled?
    }
  end

  private

  def ensure_family_feature_enabled!
    return if DawarichSettings.family_feature_enabled?

    render json: { error: 'Family feature is not enabled' }, status: :forbidden
  end

  def ensure_user_in_family!
    return if current_api_user.in_family?

    render json: { error: 'User is not part of a family' }, status: :forbidden
  end
end
