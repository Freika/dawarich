# frozen_string_literal: true

# Shared MVT tile action: conditional caching, strict range parsing, and
# no-store error handling, extracted mechanically from the points tiles
# controller. Including controllers implement:
#   tile_query            — the query object instance (responds to #call)
#   tile_schema_version   — bumped when that endpoint's SQL/properties change
#   tile_epoch_component  — the domain epoch slice for the requested range
module TileCacheable
  extend ActiveSupport::Concern

  included do
    include SafeTimestampParser
  end

  def show
    # Auth is header-only, so URL-keyed caches need Vary to keep users' tiles apart.
    response.headers['Vary'] = [response.headers['Vary'], 'Authorization'].compact.join(', ')

    # A partial or unparsable range used to fall back to "now"/whole-account in
    # the query: the caller silently got a different window than it asked for,
    # over the one query shape that can never be cached. Asking for no range at
    # all is still a deliberate, deterministic request for everything.
    if range_requested? && !cacheable_range?
      force_uncacheable_response
      return render json: { error: 'Both start_at and end_at must be present and parsable' },
                    status: :bad_request
    end

    if cacheable_range?
      # Must precede fresh_when, or a 304 goes out without Cache-Control.
      expires_in 5.minutes, public: false
      fresh_when(etag: tile_etag, public: false)
      return if performed?
    else
      # No range means an unbounded scan whose content moves as rows arrive.
      force_uncacheable_response
    end

    result = tile_query.call

    if result.truncated?
      # Unreachable by construction — firing means a query bug.
      Rails.logger.warn(
        "#{self.class.name} truncated tile #{params[:z]}/#{params[:x]}/#{params[:y]}"
      )
      response.set_header('X-Dawarich-Tile-Truncated', '1')
    end

    # An empty tile is a zero-length bytea — blank only after decoding
    tile = decode_bytea(result.tile)

    return head :no_content if tile.blank?

    send_data tile, type: 'application/vnd.mapbox-vector-tile', disposition: 'inline'
  rescue Points::VectorTileQuery::InvalidTileCoordinatesError,
         Tracks::VectorTileQuery::InvalidTileCoordinatesError
    force_uncacheable_response
    render json: { error: 'Invalid tile coordinates' }, status: :bad_request
  rescue ActiveRecord::QueryCanceled
    force_uncacheable_response
    render json: { error: 'Tile query timed out' }, status: :service_unavailable
  end

  private

  # Rails recomposes Cache-Control from response.cache_control at finalization —
  # without the clear, expires_in wins and one transient error poisons the tile
  # for the full max-age. no-cache also keeps Rack::ETag from stamping an ETag.
  def force_uncacheable_response
    response.cache_control.clear
    response.headers['Cache-Control'] = 'no-store, no-cache'
    response.headers.delete('ETag')
  end

  def tile_etag
    [
      tile_schema_version,
      current_api_user.id,
      tile_epoch_component,
      # Date-truncated: the raw LITE_DATA_WINDOW.ago moves per request and
      # would make every Lite ETag unique.
      (current_api_user.data_window_start.to_date if current_api_user.plan_restricted?),
      params[:z], params[:x], params[:y],
      cacheable_start_at, cacheable_end_at
    ]
  end

  def range_requested?
    params[:start_at].present? || params[:end_at].present?
  end

  # A reversed range parses fine but can never match a row, so without this it
  # would be cached — an empty tile served under max-age for a live account.
  def cacheable_range?
    cacheable_start_at.present? && cacheable_end_at.present? &&
      cacheable_start_at <= cacheable_end_at
  end

  def cacheable_start_at
    @cacheable_start_at ||= parse_cacheable_timestamp(params[:start_at])
  end

  def cacheable_end_at
    @cacheable_end_at ||= parse_cacheable_timestamp(params[:end_at])
  end

  # Stricter than safe_timestamp, which substitutes "now" for garbage — fine
  # for querying, poison for an ETag (content would drift under a constant key).
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

  # Same bounds and zone semantics as SafeTimestampParser — keeps the ETag
  # window identical to the query window and caps TileEpoch's year-key fan-out.
  def clamp_timestamp(value)
    value.clamp(Time.zone.parse('1970-01-01').to_i, Time.zone.parse('2100-01-01').to_i)
  end

  # Postgres bytea arrives hex-encoded, MapLibre needs raw protobuf bytes
  def decode_bytea(value)
    return value unless value.is_a?(String) && value.start_with?('\x')

    [value.delete_prefix('\x')].pack('H*')
  end
end
