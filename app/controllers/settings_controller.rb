# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!

  def index
  end

  def update
    current_user.update(settings: settings_params)

    flash.now[:notice] = 'Settings updated'

    redirect_to settings_path, notice: 'Settings updated'
  end

  def theme
    current_user.update(theme: params[:theme])

    redirect_back(fallback_location: root_path)
  end

  def generate_api_key
    current_user.update(api_key: SecureRandom.hex)

    redirect_back(fallback_location: root_path)
  end

  private

  def settings_params
    params.require(:settings).permit(
      :meters_between_routes, :minutes_between_routes, :fog_of_war_meters
    )
  end
end
