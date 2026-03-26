# frozen_string_literal: true

class Settings::MapsController < ApplicationController
  before_action :authenticate_user!

  def index
    @maps = current_user.safe_settings.maps
    @maplibre_style = current_user.safe_settings.maps_maplibre_style || 'light'
  end

  def update
    merged = settings_params.to_h
    merged['hidden_tile_categories'] = parse_json_array(merged['hidden_tile_categories'])
    merged['disabled_poi_groups'] = parse_json_array(merged['disabled_poi_groups'])

    # Lite cloud users cannot customize map layers or POI groups
    unless DawarichSettings.self_hosted? || current_user.pro?
      merged.delete('hidden_tile_categories')
      merged.delete('disabled_poi_groups')
    end

    current_user.settings['maps'] = merged
    current_user.save!

    redirect_to settings_maps_path, notice: 'Settings updated'
  end

  private

  def settings_params
    params.require(:maps).permit(:name, :url, :distance_unit, :preferred_version,
                                 :hidden_tile_categories, :disabled_poi_groups)
  end

  def parse_json_array(value)
    return [] if value.blank?
    return value if value.is_a?(Array)

    JSON.parse(value)
  rescue JSON::ParserError
    []
  end
end
