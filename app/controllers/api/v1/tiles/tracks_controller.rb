# frozen_string_literal: true

class Api::V1::Tiles::TracksController < ApiController
  include TileCacheable

  # ETag material — bump when Tracks::VectorTileQuery's SQL or its emitted
  # properties change.
  TILE_SCHEMA_VERSION = 1

  private

  def tile_schema_version
    TILE_SCHEMA_VERSION
  end

  def tile_epoch_component
    Tracks::TileEpoch.etag_component(current_api_user.id, cacheable_start_at, cacheable_end_at)
  end

  def tile_query
    Tracks::VectorTileQuery.new(
      scope: filtered_tracks,
      z: params[:z],
      x: params[:x],
      y: params[:y]
    )
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
