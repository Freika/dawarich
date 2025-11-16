# frozen_string_literal: true

class Api::V1::Families::LocationsController < ApiController
  before_action :ensure_family_feature_enabled!
  
  # Skip API key auth for toggle action (use session auth instead for browser)
  skip_before_action :authenticate_api_key, only: [:toggle]
  before_action :authenticate_user!, only: [:toggle]
  before_action :ensure_user_in_family!

  def index
    family_locations = Families::Locations.new(current_api_user).call

    render json: {
      locations: family_locations,
      updated_at: Time.current.iso8601,
      sharing_enabled: current_api_user.family_sharing_enabled?
    }
  end

  def toggle
    result = Families::UpdateLocationSharing.new(
      user: current_user,
      enabled: params[:enabled],
      duration: params[:duration]
    ).call

    render json: result.payload, status: result.status
  end

  private

  def ensure_user_in_family!
    user = action_name == 'toggle' ? current_user : current_api_user
    return if user&.in_family?

    render json: { error: 'User is not part of a family' }, status: :forbidden
  end
end
