# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  def index
    @tracks =
      current_api_user.tracks.where(id: params[:ids]).page(params[:page])
                      .per(params[:per_page] || 100)

    serialized_tracks =
      @tracks.map { |track| Api::TrackSerializer.new(track).call }

    response.set_header('X-Current-Page', @tracks.current_page.to_s)
    response.set_header('X-Total-Pages', @tracks.total_pages.to_s)

    render json: serialized_tracks
  end

  def show
    @track = current_api_user.tracks.find(params[:id])

    render json: Api::TrackSerializer.new(@track).call
  end
end
