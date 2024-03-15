class HomeController < ApplicationController
  def index
    if current_user
      redirect_to points_url
    end

    @points = current_user.points if current_user
  end
end
