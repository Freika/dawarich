# frozen_string_literal: true

class SetPointsTimestampFromGeojsonDate < ActiveRecord::Migration[8.0]
  # Raw SQL: loading the Point AR model couples this migration to HEAD's
  # associations (country, track) and any future enum/scope additions, which
  # is exactly the long-jump upgrade hazard documented in #2362. Postgres can
  # parse the embedded ISO timestamp directly.
  def up
    execute(<<~SQL.squish)
      UPDATE points
      SET timestamp = EXTRACT(EPOCH FROM (raw_data->'properties'->>'date')::timestamptz)::bigint
      WHERE timestamp IS NULL
        AND raw_data IS NOT NULL
        AND raw_data ? 'properties'
        AND raw_data->'properties' ? 'date'
        AND (raw_data->'properties'->>'date') ~ '^[0-9]{4}-'
    SQL
  end

  def down
    # No-op: we don't want to revert valid timestamps to NULL.
  end
end
