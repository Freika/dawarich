# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    redirect_to map_url if current_user
  end
end
