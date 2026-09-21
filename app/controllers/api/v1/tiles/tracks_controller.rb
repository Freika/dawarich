# frozen_string_literal: true

class Api::V1::Tiles::TracksController < ApiController
  include TileCacheable

  # ETag material — bump when Tracks::VectorTileQuery's SQL or its emitted
  # properties change.
  TILE_SCHEMA_VERSION = 6

  private

  def tile_schema_version
    [TILE_SCHEMA_VERSION, speed_coloring?]
  end

  def tile_epoch_component
    tracks_epoch = Tracks::TileEpoch.etag_component(current_api_user.id, cacheable_start_at, cacheable_end_at)
    points_epoch = Points::TileEpoch.etag_component(current_api_user.id,
                                                    cacheable_start_at, cacheable_end_at)
    [tracks_epoch, points_epoch]
  end

  def tile_query
    options = {
      scope: filtered_tracks,
      z: params[:z],
      x: params[:x],
      y: params[:y]
    }
    if cacheable_range? || params[:import_id].present?
      options[:clip_points_scope] = current_api_user.scoped_points.without_raw_data.not_anomaly
      if cacheable_range?
        options[:clip_start_at] = cacheable_start_at
        options[:clip_end_at] = cacheable_end_at
      end
      options[:clip_import_id] = params[:import_id]
    end
    return Tracks::VectorTileQuery.new(**options) unless speed_coloring?

    Tracks::SpeedVectorTileQuery.new(points_scope: options[:clip_points_scope] || speed_points_scope, **options)
  end

  def speed_coloring?
    params[:speed_coloring] == 'true'
  end

  def filtered_tracks
    scope = current_api_user.scoped_tracks
    if params[:import_id].present?
      track_ids = current_api_user.scoped_points
                                  .where(import_id: params[:import_id])
                                  .where.not(track_id: nil)
                                  .select(:track_id)
      scope = scope.where(id: track_ids)
    end

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    return scope unless start_at || end_at

    # Overlap semantics, same as Tracks::IndexQuery: a track clipped by the
    # range edge still renders.
    scope.where('end_at >= ? AND start_at <= ?',
                Time.zone.at(start_at || 0), Time.zone.at(end_at || Time.zone.now.to_i))
  end

  def speed_points_scope
    scope = current_api_user.scoped_points
    return scope if params[:import_id].blank?

    scope.where(import_id: params[:import_id])
  end
end
