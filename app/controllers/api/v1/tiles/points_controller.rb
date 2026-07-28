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

    # PostGIS returns a zero-length bytea for an empty tile, blank only once unpacked
    tile = decode_bytea(tile)

    return head :no_content if tile.blank?

    response.headers['Cache-Control'] = 'no-store'
    send_data tile, type: 'application/vnd.mapbox-vector-tile', disposition: 'inline'
  rescue Points::VectorTileQuery::InvalidTileCoordinatesError
    render json: { error: 'Invalid tile coordinates' }, status: :bad_request
  end

  private

  # Postgres bytea arrives hex-encoded, MapLibre needs raw protobuf bytes
  def decode_bytea(value)
    return value unless value.is_a?(String) && value.start_with?('\x')

    [value.delete_prefix('\x')].pack('H*')
  end

  def filtered_points
    scope = scoped_points.without_raw_data

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    return scope unless start_at || end_at

    scope.where(timestamp: (start_at || 0)..(end_at || Time.zone.now.to_i))
  end
end
