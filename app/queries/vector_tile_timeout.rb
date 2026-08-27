# frozen_string_literal: true

# Statement-timeout bound shared by the vector tile queries. The default keeps
# a runaway tile from occupying a worker slot; self-hosted instances where
# large ranges legitimately exceed it can raise the bound via
# VECTOR_TILES_QUERY_TIMEOUT_MS without a code change.
module VectorTileTimeout
  DEFAULT_QUERY_TIMEOUT_MS = 5_000

  def self.query_timeout_ms
    configured = Integer(ENV.fetch('VECTOR_TILES_QUERY_TIMEOUT_MS', ''), exception: false)
    configured&.positive? ? configured : DEFAULT_QUERY_TIMEOUT_MS
  end
end
