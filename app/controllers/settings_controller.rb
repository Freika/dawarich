# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!

  def theme
    current_user.update(theme: params[:theme])

    redirect_back(fallback_location: root_path)
  end
end
