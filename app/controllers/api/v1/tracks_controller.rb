# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  def index
    start_time = parse_timestamp(params[:start_at])
    end_time = parse_timestamp(params[:end_at])

    # Find tracks that overlap with the date range
    @tracks = current_api_user.tracks
      .where('start_at <= ? AND end_at >= ?', end_time, start_time)
      .order(:start_at)

    render json: { tracks: @tracks }
  end

  def create
    tracks_created = Tracks::CreateFromPoints.new(current_api_user).call

    render json: {
      message: "#{tracks_created} tracks created successfully",
      tracks_created: tracks_created
    }
  end

  private

  def parse_timestamp(timestamp_param)
    return Time.current if timestamp_param.blank?

    # Handle both Unix timestamps and ISO date strings
    if timestamp_param.to_s.match?(/^\d+$/)
      Time.zone.at(timestamp_param.to_i)
    else
      Time.zone.parse(timestamp_param)
    end
  rescue ArgumentError
    Time.current
  end
end
