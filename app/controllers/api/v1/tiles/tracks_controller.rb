# frozen_string_literal: true

class Api::V1::Tiles::TracksController < ApiController
  include TileCacheable

  # ETag material — bump when Tracks::VectorTileQuery's SQL or its emitted
  # properties change.
  TILE_SCHEMA_VERSION = 2

  rescue_from Tracks::SpeedVectorTileQuery::FeatureLimitError do
    force_uncacheable_response
    render json: { error: 'Too many route segments in this tile. Zoom in or shorten the date range.' },
           status: :service_unavailable
  end

  private

  def tile_schema_version
    [TILE_SCHEMA_VERSION, speed_coloring?]
  end

  def tile_epoch_component
    tracks_epoch = Tracks::TileEpoch.etag_component(current_api_user.id, cacheable_start_at, cacheable_end_at)
    return tracks_epoch unless speed_coloring?

    # Overlap semantics render whole tracks, including their portions outside
    # the requested dates. Point edits in those portions must invalidate too.
    first_at, last_at = filtered_tracks.pick(Arel.sql('MIN(start_at), MAX(end_at)'))
    [tracks_epoch, Points::TileEpoch.etag_component(current_api_user.id, first_at, last_at)]
  end

  def tile_query
    options = {
      scope: filtered_tracks,
      z: params[:z],
      x: params[:x],
      y: params[:y]
    }
    return Tracks::VectorTileQuery.new(**options) unless speed_coloring?

    Tracks::SpeedVectorTileQuery.new(points_scope: current_api_user.scoped_points, **options)
  end

  def speed_coloring?
    params[:speed_coloring] == 'true'
  end

  def filtered_tracks
    scope = current_api_user.scoped_tracks

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    return scope unless start_at || end_at

    # Overlap semantics, same as Tracks::IndexQuery: a track clipped by the
    # range edge still renders.
    scope.where('end_at >= ? AND start_at <= ?',
                Time.zone.at(start_at || 0), Time.zone.at(end_at || Time.zone.now.to_i))
  end
end
