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
      # truncated slice would place the segment at the wrong times), can
      # never anchor. Auto-classified leftovers are deleted (reclassification
      # regenerates them); manual corrections are user data and stay behind,
      # index-anchored — the id cursor advances past them, so no reselection.
      TrackSegment.where(id: ids, start_at: nil, corrected_at: nil).delete_all

      self.class.perform_later(ids.last)
    end

    # Synchronous just-in-time anchoring for legacy index-anchored rows a
    # caller needs resolved NOW (e.g. reclassification clipping around manual
    # corrections before the async backfill reached their track).
    def self.anchor_now(ids)
      new.anchor_rows(ids) if ids.any?
    end

    def anchor_rows(ids, retried: false)
      # Savepoint so a unique violation doesn't poison any surrounding
      # transaction before the rescue below recovers from it.
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute(anchor_sql(ids))
      end
    rescue ActiveRecord::RecordNotUnique
      if retried
        anchor_rows_individually(ids)
      else
        remove_duplicate_anchors(ids)
        anchor_rows(ids, retried: true)
      end
    end

    private

    # Collisions the batch dedup can't resolve (e.g. an unanchored row whose
    # computed start_at matches a segment anchored in an earlier batch) must
    # not halt the backfill for everything behind the cursor: anchor row by
    # row and leave the offenders unanchored — auto rows are duplicate
    # representations and get deleted by the caller; corrected rows stay.
    def anchor_rows_individually(ids)
      ids.each do |id|
        ActiveRecord::Base.transaction(requires_new: true) do
          ActiveRecord::Base.connection.execute(anchor_sql([id]))
        end
      rescue ActiveRecord::RecordNotUnique => e
        ExceptionReporter.call(e, "TimeAnchorBackfill: segment #{id} collides with an existing anchor")
      end
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
