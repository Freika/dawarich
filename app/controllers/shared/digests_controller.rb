# frozen_string_literal: true

class Shared::DigestsController < ApplicationController
  include DefaultDateTimePreferences
  include FlashStreamable
  include SharingToggleable

  helper Users::DigestsHelper
  helper CountryFlagHelper

  before_action :authenticate_user!, except: [:show]
  before_action :authenticate_active_user!, only: [:update]

  def show
    @digest = Users::Digest.find_by(sharing_uuid: params[:uuid])

    unless @digest&.public_accessible? && @digest.user
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

    toggle_sharing(@digest, 'controllers.shared.digests') { |uuid| shared_users_digest_url(uuid) }
  end
end
