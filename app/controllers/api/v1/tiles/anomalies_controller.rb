# frozen_string_literal: true

class Api::V1::Tiles::AnomaliesController < ApiController
  include TileCacheable

  # ETag material — bump when the tile SQL or its emitted properties change.
  # Rides the SHARED Points::VectorTileQuery: a change to its SQL bumps this
  # AND the points version.
  TILE_SCHEMA_VERSION = 1

  private

  def tile_schema_version
    TILE_SCHEMA_VERSION
  end

  # Anomaly flips already bump the POINTS epoch (AnomalyFilter, backfill), so
  # anomaly tiles share it rather than growing a third namespace.
  def tile_epoch_component
    Points::TileEpoch.etag_component(current_api_user.id, cacheable_start_at, cacheable_end_at)
  end

  def tile_query
    Points::VectorTileQuery.new(
      scope: filtered_anomalies,
      z: params[:z],
      x: params[:x],
      y: params[:y],
      # Where popups exist (z >= attribute zoom), 1px cells keep anomalies
      # unmerged so MIN(accuracy) can't mislabel a popup reason; below that the
      # benchmarked 4px tier still bounds pathological all-anomaly accounts.
      grid_px_override: 1,
      # Classic mode makes anomalies clickable at EVERY zoom — carry the
      # attributes at low zoom too (sparse scope, cost is negligible).
      attributes_at_all_zooms: true,
      # Popup reason branches on accuracy.
      extra_property_columns: [:accuracy]
    )
  end

  def filtered_anomalies
    scope = scoped_points.without_raw_data.anomaly

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    return scope unless start_at || end_at

    scope.where(timestamp: (start_at || 0)..(end_at || Time.zone.now.to_i))
  end
end
