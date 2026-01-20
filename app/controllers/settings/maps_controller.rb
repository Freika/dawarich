# frozen_string_literal: true

class Settings::MapsController < ApplicationController
  before_action :authenticate_user!

  def index
    @maps = current_user.safe_settings.maps

    today = TimezoneHelper.today_in_timezone(current_user.timezone)
    @tile_usage = (today - 7.days).upto(today).map do |date|
      [
        date.to_s,
        Rails.cache.read("dawarich_map_tiles_usage:#{current_user.id}:#{date}") || 0
      ]
    end
  end

  def update
    current_user.settings['maps'] = settings_params
    current_user.save!

    redirect_to settings_maps_path, notice: 'Settings updated'
  end

  private

  def settings_params
    params.require(:maps).permit(:name, :url, :distance_unit, :preferred_version)
  end
end
