# frozen_string_literal: true

class Shared::LinksController < ApplicationController
  layout 'shared'

  skip_before_action :verify_authenticity_token, only: %i[show unlock]
  before_action :set_noindex
  before_action :load_link
  before_action :verify_phrase, only: :show

  def show
    @link.touch_access!
    @resource = @link.resource
    render :show
  end

  def unlock
    if ActiveSupport::SecurityUtils.secure_compare(@link.magic_phrase.to_s, params[:phrase].to_s)
      set_unlock_cookie
      redirect_to public_shared_link_path(@link.id)
    else
      Rails.logger.warn("Shared link unlock failed: link=#{@link.id} ip=#{request.remote_ip}")
      flash.now[:error] = "That phrase didn't work. Try again."
      render :phrase_prompt, status: :unauthorized
    end
  end

  private

  def load_link
    @link = SharedLink.active.find_by(id: params[:id])
    return if @link

    render 'shared/links/not_found', status: :not_found, layout: 'shared'
  end

  def verify_phrase
    return if @link.magic_phrase.blank?
    return if cookies.encrypted[unlock_cookie_key] == @link.unlock_token

    render :phrase_prompt, status: :unauthorized
  end

  def set_unlock_cookie
    cookies.encrypted[unlock_cookie_key] = {
      value: @link.unlock_token,
      expires: @link.expires_at || 30.days.from_now,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
  end

  def unlock_cookie_key
    "shared_link_#{@link.id}"
  end

  def set_noindex
    response.set_header('X-Robots-Tag', 'noindex, nofollow')
  end
end
