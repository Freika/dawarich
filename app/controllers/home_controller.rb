# frozen_string_literal: true

class HomeController < ApplicationController
  include ApplicationHelper

  def index
    # redirect_to 'https://dawarich.app', allow_other_host: true and return unless SELF_HOSTED

    if current_user.nil? && DawarichSettings.oidc_auto_login_enabled?
      # Keep alerts from failed sign-ins visible on the sign-in page.
      flash.keep
      redirect_to new_user_session_path(auto_login: params[:auto_login]) and return
    end

    redirect_to preferred_map_path if current_user

    @points = current_user.points.without_raw_data if current_user
  end
end
