# frozen_string_literal: true

class Shared::DigestsController < ApplicationController
  helper Users::DigestsHelper

  before_action :authenticate_user!, except: [:show]
  before_action :authenticate_active_user!, only: [:update]

  def show
    @digest = Users::Digest.find_by(sharing_uuid: params[:uuid])

    unless @digest&.public_accessible?
      return redirect_to root_path,
                         alert: 'Shared digest not found or no longer available'
    end

    @year = @digest.year
    @user = @digest.user
    @distance_unit = @user.safe_settings.distance_unit || 'km'
    @is_public_view = true

    render 'users/digests/public_year'
  end

  def update
    @year = params[:year].to_i
    @digest = current_user.digests.yearly.find_by(year: @year)

    return head :not_found unless @digest

    if params[:enabled] == '1'
      @digest.enable_sharing!(expiration: params[:expiration] || '24h')
      sharing_url = shared_users_digest_url(@digest.sharing_uuid)

      render json: {
        success: true,
        sharing_url: sharing_url,
        message: 'Sharing enabled successfully'
      }
    else
      @digest.disable_sharing!

      render json: {
        success: true,
        message: 'Sharing disabled successfully'
      }
    end
  rescue StandardError
    render json: {
      success: false,
      message: 'Failed to update sharing settings'
    }, status: :unprocessable_content
  end
end
