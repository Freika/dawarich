# frozen_string_literal: true

class Api::V1::Tiles::PointsController < ApiController
  include SafeTimestampParser

  def show
    tile = Points::VectorTileQuery.new(
      scope: filtered_points,
      z: params[:z],
      x: params[:x],
      y: params[:y]
    ).call

    return head :no_content if tile.blank?

    # Postgres bytea may come back as a hex-encoded string (for example "\x1a2b...").
    # MapLibre expects raw protobuf bytes, not the escaped hex representation.
    tile = [tile.delete_prefix('\x')].pack('H*') if tile.is_a?(String) && tile.start_with?('\x')

    response.headers['Cache-Control'] = 'no-store'
    send_data tile, type: 'application/vnd.mapbox-vector-tile', disposition: 'inline'
  rescue Points::VectorTileQuery::InvalidTileCoordinatesError
    render json: { error: 'Invalid tile coordinates' }, status: :bad_request
  end

  private

  def filtered_points
    scope = scoped_points.without_raw_data

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    return scope unless start_at || end_at

    scope.where(timestamp: (start_at || 0)..(end_at || Time.zone.now.to_i))
  end
end
