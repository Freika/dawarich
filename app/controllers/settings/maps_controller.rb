# frozen_string_literal: true

class Settings::MapsController < ApplicationController
  before_action :authenticate_user!

  def index
    @maps = current_user.safe_settings.maps
  end

  # This page only manages V1 (Leaflet) settings; V2 settings (distance
  # unit, tile categories, POIs, vector tiles) live in the map panel and
  # are written via the settings API — merge so they survive this form.
  def update
    current_user.settings['maps'] =
      current_user.settings['maps'].to_h.merge(settings_params.to_h)
    current_user.save!

    redirect_to settings_maps_path, notice: 'Settings updated'
  end

  private

  def settings_params
    params.require(:maps).permit(:name, :url, :preferred_version)
  end
end
