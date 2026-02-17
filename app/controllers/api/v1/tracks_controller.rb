# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  def index
    tracks_query = Tracks::IndexQuery.new(user: current_api_user, params: params)
    paginated_tracks = tracks_query.call

    geojson = Tracks::GeojsonSerializer.new(paginated_tracks).call

    tracks_query.pagination_headers(paginated_tracks).each do |header, value|
      response.set_header(header, value)
    end

    render json: geojson
  end

  def show
    track = current_api_user.tracks.includes(:track_segments).find(params[:id])
    geojson = Tracks::GeojsonSerializer.new(track, include_segments: true).call

    render json: geojson
  end
end
