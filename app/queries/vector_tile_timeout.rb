# frozen_string_literal: true

# Statement-timeout bound shared by the vector tile queries. The default keeps
# a runaway tile from occupying a worker slot; self-hosted instances where
# large ranges legitimately exceed it can raise the bound via
# VECTOR_TILES_QUERY_TIMEOUT_MS without a code change.
#
# Tile queries also run with JIT off: compiling a tile query costs seconds
# while the query itself takes milliseconds, so several tiles at once blow
# the timeout.
module VectorTileTimeout
  DEFAULT_QUERY_TIMEOUT_MS = 5_000

  def self.query_timeout_ms
    configured = Integer(ENV.fetch('VECTOR_TILES_QUERY_TIMEOUT_MS', ''), exception: false)
    configured&.positive? ? configured : DEFAULT_QUERY_TIMEOUT_MS
  end

  def self.within(conn, label)
    conn.transaction do
      conn.exec_query('SET LOCAL jit = off', "#{label} JIT")
      conn.exec_query("SET LOCAL statement_timeout = #{query_timeout_ms}", "#{label} Timeout")
      yield conn
    end
  end
end
