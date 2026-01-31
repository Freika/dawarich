# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!

  def theme
    current_user.update(theme: params[:theme])

    redirect_back(fallback_location: root_path)
  end

  def generate_api_key
    current_user.update(api_key: SecureRandom.hex)

    redirect_back(fallback_location: root_path)
  end
end
