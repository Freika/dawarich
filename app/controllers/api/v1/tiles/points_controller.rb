# frozen_string_literal: true

class Api::V1::Tiles::PointsController < ApiController
  include TileCacheable

  # ETag material — bump when the tile SQL or its emitted properties change,
  # so a deploy invalidates cached tiles.
  TILE_SCHEMA_VERSION = 7

  private

  def tile_schema_version
    [TILE_SCHEMA_VERSION, privacy_zone_masker.fingerprint]
  end

  def tile_privacy_masker
    @tile_privacy_masker ||= privacy_zone_masker.near_tile(params[:z], params[:x], params[:y])
  end

  def tile_epoch_component
    @tile_epoch_component ||=
      Points::Revision.for_user(current_api_user.id, start_at: cacheable_start_at, end_at: cacheable_end_at)
  end

  def tile_query
    Points::VectorTileQuery.new(
      scope: filtered_points,
      z: params[:z],
      x: params[:x],
      y: params[:y],
      fence_key: (fence_key if cacheable_range?)
    )
  end

  # Same ingredients as the ETag minus the tile address: the revision moves
  # when points change, and the Lite window is date-truncated like the ETag's.
  # Without a range there is no ETag to share the revision lookup with, so the
  # query falls back to keying on its own SQL.
  def fence_key
    [
      current_api_user.id, tile_epoch_component,
      (current_api_user.data_window_start.to_date if current_api_user.plan_restricted?),
      cacheable_start_at, cacheable_end_at, params[:import_id].presence
    ]
  end

  def filtered_points
    # Parity with the classic points layer — anomalies render in their own layer.
    scope = tile_privacy_masker.mask_points(scoped_points.without_raw_data.not_anomaly)
    scope = scope.where(import_id: params[:import_id]) if params[:import_id].present?

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    # No range = whole-account scan at low zoom; the statement timeout caps the
    # worst case, and the map JS always sends both params.
    return scope unless start_at || end_at

    scope.where(timestamp: (start_at || 0)..(end_at || Time.zone.now.to_i))
  end
end
