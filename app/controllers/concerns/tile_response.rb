# frozen_string_literal: true

module TileResponse
  extend ActiveSupport::Concern

  private

  # Rails recomposes Cache-Control from response.cache_control at finalization —
  # without the clear, expires_in wins and one transient error poisons the tile
  # for the full max-age. no-cache also keeps Rack::ETag from stamping an ETag.
  def force_uncacheable_response
    response.cache_control.clear
    response.headers['Cache-Control'] = 'no-store, no-cache'
    response.headers.delete('ETag')
  end

  def record_tile_metrics(started_at)
    outcome = case response.status
              when 200, 204 then 'success'
              when 304 then 'not_modified'
              when 400 then 'invalid'
              when 503 then 'failure'
              else "http_#{response.status}"
              end
    tags = { layer: tile_metric_layer, outcome: outcome }
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    log_tile_failure(tags, duration) unless %w[success not_modified].include?(outcome)
    Yabeda.dawarich_map.tile_requests_total.increment(tags)
    Yabeda.dawarich_map.tile_request_duration_seconds.measure(tags, duration)
  rescue StandardError => e
    Rails.logger.warn("event=map_tile.metrics_failed error_class=#{e.class}")
  end

  def log_tile_failure(tags, duration)
    Rails.logger.warn(
      "event=map.tile_request layer=#{tags.fetch(:layer)} outcome=#{tags.fetch(:outcome)} " \
      "status=#{response.status} duration_ms=#{(duration * 1000).round(1)}"
    )
  end

  def tile_metric_layer
    self.class.name.demodulize.delete_suffix('Controller').underscore
  end

  # Postgres bytea arrives hex-encoded, MapLibre needs raw protobuf bytes
  def decode_bytea(value)
    return value unless value.is_a?(String) && value.start_with?('\x')

    [value.delete_prefix('\x')].pack('H*')
  end
end
