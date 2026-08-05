# frozen_string_literal: true

module TrackSegments
  # One-time backfill converting index-based track_segments to time anchors
  # (start_at/end_at) with baked LineString geometry. Batched by id cursor,
  # idempotent, self-re-enqueuing until no unanchored rows remain.
  class TimeAnchorBackfillJob < ApplicationJob
    queue_as :data_migrations

    BATCH = 1_000

    def perform(from_id = 0)
      ids = TrackSegment.where(id: (from_id + 1)..)
                        .where(start_at: nil).where.not(start_index: nil)
                        .order(:id).limit(BATCH).pluck(:id)
      return if ids.empty?

      anchor_rows(ids)

      # Rows whose index range matched no points, or matched an incomplete
      # slice (points deleted since the indexes were computed — anchoring a
      # truncated slice would place the segment at the wrong times), would
      # loop forever: drop their indexes so the cursor stops selecting them.
      TrackSegment.where(id: ids, start_at: nil).update_all(start_index: nil, end_index: nil)

      self.class.perform_later(ids.last)
    end

    private

    def anchor_rows(ids, retried: false)
      ActiveRecord::Base.connection.execute(anchor_sql(ids))
    rescue ActiveRecord::RecordNotUnique
      raise if retried

      remove_duplicate_anchors(ids)
      anchor_rows(ids, retried: true)
    end

    def anchor_sql(ids)
      <<~SQL.squish
        UPDATE track_segments ts SET
          start_at = to_timestamp(sub.min_ts), end_at = to_timestamp(sub.max_ts),
          path = CASE WHEN sub.n >= 2 THEN sub.line ELSE NULL END
        FROM (
          SELECT ts2.id, MIN(p.timestamp) AS min_ts, MAX(p.timestamp) AS max_ts,
                 COUNT(*) AS n, ST_MakeLine(p.lonlat::geometry ORDER BY p.timestamp, p.id) AS line
          FROM track_segments ts2
          JOIN LATERAL (
            SELECT p.timestamp, p.id, p.lonlat FROM points p
            WHERE p.track_id = ts2.track_id
            ORDER BY p.timestamp, p.id
            OFFSET ts2.start_index LIMIT GREATEST(ts2.end_index - ts2.start_index + 1, 0)
          ) p ON TRUE
          WHERE ts2.id IN (#{ids.join(',')})
          GROUP BY ts2.id
        ) sub
        WHERE ts.id = sub.id AND ts.start_at IS NULL
          AND sub.n = ts.end_index - ts.start_index + 1
      SQL
    end

    # Historically drifted indexes can compute identical (track_id, start_at)
    # pairs. Keep corrected rows and the lowest-id auto row; delete the rest.
    def remove_duplicate_anchors(ids)
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        DELETE FROM track_segments del USING (
          SELECT ts2.id,
                 ROW_NUMBER() OVER (
                   PARTITION BY ts2.track_id, computed.min_ts
                   ORDER BY (ts2.corrected_at IS NOT NULL) DESC, ts2.id
                 ) AS rn
          FROM track_segments ts2
          JOIN LATERAL (
            SELECT MIN(p.timestamp) AS min_ts FROM (
              SELECT p2.timestamp FROM points p2
              WHERE p2.track_id = ts2.track_id
              ORDER BY p2.timestamp, p2.id
              OFFSET ts2.start_index LIMIT GREATEST(ts2.end_index - ts2.start_index + 1, 0)
            ) p
          ) computed ON TRUE
          WHERE ts2.id IN (#{ids.join(',')}) AND ts2.start_at IS NULL
        ) ranked
        WHERE del.id = ranked.id AND ranked.rn > 1 AND del.corrected_at IS NULL
      SQL
    end
  end
end
