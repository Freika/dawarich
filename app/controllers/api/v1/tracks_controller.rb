# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  def index
    tracks_query = Tracks::IndexQuery.new(user: current_api_user, params: params)
    paginated_tracks = tracks_query.call

    geojson = Tracks::GeojsonSerializer.new(paginated_tracks, geometry: geometry_variant).call

    tracks_query.pagination_headers(paginated_tracks).each do |header, value|
      response.set_header(header, value)
    end

    render json: geojson
  end

  def show
    track = current_api_user.tracks.includes(:track_segments).find(params[:id])
    geojson = Tracks::GeojsonSerializer.new(track, include_segments: true, geometry: geometry_variant).call

    if params[:import_id].present?
      points_scope = current_api_user.scoped_points.without_raw_data.not_anomaly
      summary = Tracks::ImportGeometryQuery.new(points_scope:, import_id: params[:import_id])
                                           .summary_for(track_id: track.id)
      return head :not_found unless summary

      start_at = Time.zone.at(summary[:start_timestamp]).iso8601
      end_at = Time.zone.at(summary[:end_timestamp]).iso8601
      duration = summary[:end_timestamp] - summary[:start_timestamp]
      feature = geojson[:features].first
      feature[:geometry] = summary[:geometry]
      feature[:properties].merge!(start_at:, end_at:, duration:, distance: summary[:distance].round,
                                  avg_speed: duration.positive? ? (summary[:distance] * 3.6 / duration) : 0.0,
                                  segments: [], mode_timeline: [])
    end

    render json: geojson
  end

  private

  def geometry_variant
    variant = params.fetch(:geometry, 'original').to_s
    return variant if Tracks::DisplayPath::VARIANTS.include?(variant)

    'original'
  end
end
