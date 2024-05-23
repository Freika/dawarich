# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    redirect_to map_url if current_user

    @points = current_user.points.without_raw_data if current_user
  end
end
