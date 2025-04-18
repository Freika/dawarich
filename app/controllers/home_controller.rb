# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    # redirect_to 'https://dawarich.app', allow_other_host: true and return unless SELF_HOSTED

    redirect_to map_url if current_user

    @points = current_user.tracked_points.without_raw_data if current_user
  end
end
