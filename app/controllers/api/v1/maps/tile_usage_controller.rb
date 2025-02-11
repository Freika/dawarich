# frozen_string_literal: true

class Api::V1::Maps::TileUsageController < ApiController
  def create
    Maps::TileUsage::Track.new(tile_usage_params[:count].to_i).call

    head :ok
  end

  private

  def tile_usage_params
    params.require(:tile_usage).permit(:count)
  end
end
