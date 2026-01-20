# frozen_string_literal: true

class Api::V1::Tracks::PointsController < ApiController
  def index
    track = current_api_user.tracks.find(params[:track_id])

    points = track.points
                  .without_raw_data
                  .order(timestamp: :asc)

    serialized_points = points.map { |point| Api::PointSerializer.new(point).call }

    render json: serialized_points
  end
end
