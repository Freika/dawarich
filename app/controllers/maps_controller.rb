class MapsController < ApplicationController
  def index
    redirect_to maps_maplibre_path
  end
end
