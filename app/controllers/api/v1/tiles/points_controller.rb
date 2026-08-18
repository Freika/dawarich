# frozen_string_literal: true

class Api::V1::Tiles::PointsController < ApiController
  include TileCacheable

  # ETag material — bump when the tile SQL or its emitted properties change,
  # so a deploy invalidates cached tiles. A change to the SHARED
  # Points::VectorTileQuery SQL bumps this AND the anomalies version.
  TILE_SCHEMA_VERSION = 1

  private

  def tile_schema_version
    TILE_SCHEMA_VERSION
  end

  def tile_epoch_component
    Points::TileEpoch.etag_component(current_api_user.id, cacheable_start_at, cacheable_end_at)
  end

  def tile_query
    Points::VectorTileQuery.new(
      scope: filtered_points,
      z: params[:z],
      x: params[:x],
      y: params[:y]
    )
  end

  def filtered_points
    # Parity with the classic points layer — anomalies render in their own layer.
    scope = scoped_points.without_raw_data.not_anomaly

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    # No range = whole-account scan at low zoom; the statement timeout caps the
    # worst case, and the map JS always sends both params.
    return scope unless start_at || end_at

    scope.where(timestamp: (start_at || 0)..(end_at || Time.zone.now.to_i))
  end
end
