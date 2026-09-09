# frozen_string_literal: true

class Shared::DigestsController < ApplicationController
  include FlashStreamable

  helper Users::DigestsHelper
  helper CountryFlagHelper

  before_action :authenticate_user!, except: [:show]
  before_action :authenticate_active_user!, only: [:update]

  def show
    @digest = Users::Digest.find_by(sharing_uuid: params[:uuid])

    unless @digest&.public_accessible?
      return redirect_to root_path,
                         alert: I18n.t('controllers.shared.digests.shared_digest_not_found_or_no_longer_available')
    end

    @year = @digest.year
    @user = @digest.user
    @distance_unit = @user.safe_settings.distance_unit || 'km'
    @is_public_view = true
    @full_digest = @user.full_access?

    render 'users/digests/public_year'
  end

  def update
    @year = params[:year].to_i
    @digest = current_user.digests.yearly.find_by(year: @year)

    return head :not_found unless @digest

    if params[:enabled] == '1'
      @digest.enable_sharing!(expiration: params[:expiration] || '24h')
      @sharing_url = shared_users_digest_url(@digest.sharing_uuid)
      @message = I18n.t('controllers.shared.digests.sharing_enabled')
    else
      @digest.disable_sharing!
      @sharing_url = ''
      @message = I18n.t('controllers.shared.digests.sharing_disabled')
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('sharing-link-display',
                               partial: 'shared/sharing_link',
                               locals: { sharing_url: @sharing_url }),
          stream_flash(:success, I18n.t('controllers.shared.digests.auto_saved'))
        ]
      end
      format.json do
        render json: { success: true, sharing_url: @sharing_url, message: @message }
      end
    end
  rescue StandardError
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: stream_flash(
          :error,
          I18n.t('controllers.shared.digests.failed_to_update_sharing_settings')
        )
      end
      format.json do
        message = I18n.t('controllers.shared.digests.failed_to_update_sharing_settings')
        render json: { success: false, message: message },
               status: :unprocessable_content
      end
    end
  end
end
