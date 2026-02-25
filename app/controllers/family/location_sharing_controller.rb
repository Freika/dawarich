# frozen_string_literal: true

class Family::LocationSharingController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :ensure_user_in_family!

  def update
    result = Families::UpdateLocationSharing.new(
      user: current_user,
      enabled: params[:enabled],
      duration: params[:duration]
    ).call

    respond_to do |format|
      format.turbo_stream do
        current_user.reload
        streams = [
          turbo_stream.replace(
            "location-sharing-#{current_user.id}",
            partial: 'families/location_sharing_toggle',
            locals: { member: current_user }
          ),
          stream_flash(result.success? ? :success : :error, result.payload[:message])
        ]
        render turbo_stream: streams
      end
      format.json { render json: result.payload, status: result.status }
    end
  end

  private

  def ensure_user_in_family!
    return if current_user.in_family?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: stream_flash(:error, 'User is not part of a family'), status: :forbidden
      end
      format.json { render json: { error: 'User is not part of a family' }, status: :forbidden }
    end
  end
end
