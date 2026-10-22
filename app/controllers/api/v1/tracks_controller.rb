# frozen_string_literal: true

class Api::V1::TracksController < ApiController
  include SafeTimestampParser

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
    return render json: geojson unless clip?(track)

    summary = Tracks::PointGeometryQuery.new(
      points_scope: current_api_user.scoped_points.without_raw_data.not_anomaly,
      import_id: params[:import_id].presence, start_at: clip_range&.first, end_at: clip_range&.last
    ).summary_for(track_id: track.id)
    return head :not_found if summary.nil? && params[:import_id].present?

    apply_summary(geojson[:features].first, summary) if summary
    render json: geojson
  end

  private

  def clip?(track)
    return true if params[:import_id].present?
    return false unless clip_range

    track.start_at.to_i < clip_range.first || track.end_at.to_i > clip_range.last
  end

  def clip_range
    return if params[:start_at].blank? || params[:end_at].blank?

    @clip_range ||= [safe_timestamp(params[:start_at]), safe_timestamp(params[:end_at])]
  end

  def apply_summary(feature, summary)
    duration = summary[:end_timestamp] - summary[:start_timestamp]
    feature[:geometry] = summary[:geometry]
    feature[:properties].merge!(
      start_at: Time.zone.at(summary[:start_timestamp]).iso8601,
      end_at: Time.zone.at(summary[:end_timestamp]).iso8601,
      duration:, distance: summary[:distance].round,
      avg_speed: duration.positive? ? (summary[:distance] * 3.6 / duration) : 0.0,
      segments: [], mode_timeline: []
    )
  end
end
