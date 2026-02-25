# frozen_string_literal: true

class Api::V1::Tracks::PointsController < ApiController
  def index
    track = current_api_user.tracks.find(params[:track_id])

    # First try to get points directly associated with the track
    points = track.points.without_raw_data.includes(:country).order(timestamp: :asc)

    # If no points are associated, fall back to fetching by time range
    # This handles tracks created before point association was implemented
    if points.empty?
      points = current_api_user.points
                               .without_raw_data
                               .includes(:country)
                               .where(timestamp: track.start_at.to_i..track.end_at.to_i)
                               .order(timestamp: :asc)
    end

    # Support optional pagination (backward compatible - returns all if no page param)
    if params[:page].present?
      per_page = (params[:per_page].presence&.to_i || 1000).clamp(1, 1000)
      points = points.page(params[:page]).per(per_page)
      response.set_header('X-Current-Page', points.current_page.to_s)
      response.set_header('X-Total-Pages', points.total_pages.to_s)
    end

    serialized_points = points.map { |point| Api::PointSerializer.new(point).call }

    render json: serialized_points
  end
end
