# frozen_string_literal: true

class Family::LocationSharingController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :ensure_user_in_family!

  def update
    result = Families::UpdateLocationSharing.new(
      user: current_user,
      enabled: params[:enabled],
      duration: params[:duration]
    ).call

    render json: result.payload, status: result.status
  end

  private

  def ensure_user_in_family!
    return if current_user.in_family?

    render json: { error: 'User is not part of a family' }, status: :forbidden
  end
end
