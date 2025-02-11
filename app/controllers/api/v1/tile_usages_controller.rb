# frozen_string_literal: true

class Api::V1::TileUsagesController < ApiController
  def create
    TileUsage::Track.new(params[:tile_count].to_i).call

    head :ok
  end
end
