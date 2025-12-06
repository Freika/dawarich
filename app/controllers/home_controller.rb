# frozen_string_literal: true

class HomeController < ApplicationController
  include ApplicationHelper

  def index
    # redirect_to 'https://dawarich.app', allow_other_host: true and return unless SELF_HOSTED

    redirect_to preferred_map_path if current_user

    @points = current_user.points.without_raw_data if current_user
  end
end
