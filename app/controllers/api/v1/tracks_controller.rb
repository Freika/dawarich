# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  def index
    tracks = current_api_user.tracks

    # Date range filtering (overlap logic)
    if params[:start_at].present? && params[:end_at].present?
      start_at = Time.zone.parse(params[:start_at])
      end_at = Time.zone.parse(params[:end_at])

      # Show tracks that overlap: end_at >= start_filter AND start_at <= end_filter
      tracks = tracks.where('end_at >= ? AND start_at <= ?', start_at, end_at)
    end

    # Pagination (Kaminari)
    tracks = tracks
      .order(start_at: :desc)
      .page(params[:page])
      .per(params[:per_page] || 100)

    # Serialize to GeoJSON format
    features = tracks.map do |track|
      {
        type: 'Feature',
        geometry: RGeo::GeoJSON.encode(track.original_path),
        properties: {
          id: track.id,
          color: '#ff0000', # Red color
          start_at: track.start_at.iso8601,
          end_at: track.end_at.iso8601,
          distance: track.distance.to_i,
          avg_speed: track.avg_speed.to_f,
          duration: track.duration
        }
      }
    end

    geojson = {
      type: 'FeatureCollection',
      features: features
    }

    # Add pagination headers
    response.set_header('X-Current-Page', tracks.current_page.to_s)
    response.set_header('X-Total-Pages', tracks.total_pages.to_s)
    response.set_header('X-Total-Count', tracks.total_count.to_s)

    render json: geojson
  end
end
