# frozen_string_literal: true

class HomeController < ApplicationController
  include ApplicationHelper

  def index
    redirect_to current_user ? preferred_map_path : new_user_session_path
  end
end
