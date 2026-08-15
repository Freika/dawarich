# frozen_string_literal: true

class Api::V1::Tiles::PointsController < ApiController
  include SafeTimestampParser

  # Part of the ETag material — bump whenever the tile query shape or its
  # emitted properties change, so a deploy invalidates cached tiles instead of
  # 304-ing stale shapes at dormant users indefinitely.
  TILE_SCHEMA_VERSION = 1

  def show
    # The URL no longer identifies the user (auth is header-only), so any
    # URL-keyed cache needs Vary to keep users' tile bodies apart — on EVERY
    # response, cacheable or not, as belt to no-store's braces.
    response.headers['Vary'] = [response.headers['Vary'], 'Authorization'].compact.join(', ')

    if cacheable_range?
      # expires_in must come BEFORE fresh_when, or a 304 short-circuit goes out
      # without Cache-Control and the browser revalidates every pan.
      expires_in 5.minutes, public: false
      fresh_when(etag: tile_etag, public: false)
      return if performed?
    else
      # A one-sided or malformed range falls back to "now" inside the query,
      # so its content moves with the clock — caching it would pin stale data.
      force_uncacheable_response
    end

    result = Points::VectorTileQuery.new(
      scope: filtered_points,
      z: params[:z],
      x: params[:x],
      y: params[:y]
    ).call

    if result.truncated?
      # Mathematically unreachable (the limit exceeds the grid's cell count);
      # firing means a query bug, so make it observable rather than silent.
      Rails.logger.warn("VectorTileQuery truncated tile #{params[:z]}/#{params[:x]}/#{params[:y]}")
      response.set_header('X-Dawarich-Tile-Truncated', '1')
    end

    # PostGIS returns a zero-length bytea for an empty tile, blank only once unpacked
    tile = decode_bytea(result.tile)

    return head :no_content if tile.blank?

    send_data tile, type: 'application/vnd.mapbox-vector-tile', disposition: 'inline'
  rescue Points::VectorTileQuery::InvalidTileCoordinatesError
    force_uncacheable_response
    render json: { error: 'Invalid tile coordinates' }, status: :bad_request
  rescue ActiveRecord::QueryCanceled
    force_uncacheable_response
    render json: { error: 'Tile query timed out' }, status: :service_unavailable
  end

  private

  # Error responses run AFTER the caching headers were set and Rails composes
  # Cache-Control from response.cache_control at finalization — without the
  # clear, expires_in would win and one transient timeout poisons the tile in
  # the browser for the full max-age. no-cache (alongside no-store) also keeps
  # Rack::ETag from stamping a body-digest ETag onto the response.
  def force_uncacheable_response
    response.cache_control.clear
    response.headers['Cache-Control'] = 'no-store, no-cache'
    response.headers.delete('ETag')
  end

  def tile_etag
    [
      TILE_SCHEMA_VERSION,
      current_api_user.id,
      Points::TileEpoch.etag_component(current_api_user.id, cacheable_start_at, cacheable_end_at),
      # The EFFECTIVE window: data_window_start itself is plan-independent —
      # plan_restricted? is what turns it on. Truncated to a date because the
      # raw value is LITE_DATA_WINDOW.ago, recomputed per request; sub-second
      # precision would make every Lite ETag unique and disable caching for
      # the whole tier.
      (current_api_user.data_window_start.to_date if current_api_user.plan_restricted?),
      params[:z], params[:x], params[:y],
      cacheable_start_at, cacheable_end_at
    ]
  end

  def cacheable_range?
    cacheable_start_at.present? && cacheable_end_at.present?
  end

  def cacheable_start_at
    @cacheable_start_at ||= parse_cacheable_timestamp(params[:start_at])
  end

  def cacheable_end_at
    @cacheable_end_at ||= parse_cacheable_timestamp(params[:end_at])
  end

  # Stricter than safe_timestamp on purpose: safe_timestamp substitutes "now"
  # for absent/garbage input, which is fine for querying but poison for an
  # ETag (the content would drift under a constant cache key). Only a value
  # that parses cleanly may participate in caching.
  def parse_cacheable_timestamp(value)
    return nil if value.blank?
    return clamp_timestamp(value.to_i) if value.match?(/\A\d+\z/)

    parsed = Time.zone.parse(value)
    return nil if parsed.nil?
    # Time.zone.parse yields year-2000 epoch for unparseable strings
    return nil if parsed.year == 2000 && !value.include?('2000')

    clamp_timestamp(parsed.to_i)
  rescue ArgumentError, TypeError
    nil
  end

  # Same bounds (and same zone semantics) as SafeTimestampParser: keeps the
  # ETag window identical to the query window and caps TileEpoch's per-request
  # year-key fan-out.
  def clamp_timestamp(value)
    value.clamp(Time.zone.parse('1970-01-01').to_i, Time.zone.parse('2100-01-01').to_i)
  end

  # Postgres bytea arrives hex-encoded, MapLibre needs raw protobuf bytes
  def decode_bytea(value)
    return value unless value.is_a?(String) && value.start_with?('\x')

    [value.delete_prefix('\x')].pack('H*')
  end

  def filtered_points
    # not_anomaly keeps parity with the classic points layer — anomalies render
    # in their own layer and must not double up as ordinary tile points.
    scope = scoped_points.without_raw_data.not_anomaly

    start_at = safe_timestamp(params[:start_at]) if params[:start_at].present?
    end_at = safe_timestamp(params[:end_at]) if params[:end_at].present?
    # No range = scan of the whole account at low zoom (only the timestamp
    # index bounds z<5 tiles); the statement timeout turns the worst case into
    # a 503, and the map JS always sends both params.
    return scope unless start_at || end_at

    scope.where(timestamp: (start_at || 0)..(end_at || Time.zone.now.to_i))
  end
end
