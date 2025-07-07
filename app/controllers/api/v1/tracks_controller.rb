# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  def index
    start_at = params[:start_at]&.to_datetime&.to_i
    end_at = params[:end_at]&.to_datetime&.to_i || Time.zone.now.to_i

    tracks = current_api_user.tracks
                             .where('start_at <= ? AND end_at >= ?', Time.zone.at(end_at), Time.zone.at(start_at))
                             .order(start_at: :asc)

    track_ids = tracks.pluck(:id)
    serialized_tracks = TrackSerializer.new(current_api_user, track_ids).call

    render json: { tracks: serialized_tracks }
  end

  def create
    Tracks::CreateJob.perform_later(current_api_user.id)

    render json: { message: 'Track generation started' }
  end
end
