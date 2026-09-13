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
      rescue ActiveRecord::RecordNotUnique
        Rails.logger.info(
          "TimeAnchorBackfill: segment #{id} collides with an existing anchor"
        )
      end
    end

    # Points are numbered once per track and range-joined, rather than
    # re-scanned per segment with OFFSET start_index. Segments partition their
    # track, so numbering reads the same rows once instead of once per segment.
    def anchor_sql(ids)
      <<~SQL.squish
        UPDATE track_segments ts SET
          start_at = to_timestamp(sub.min_ts), end_at = to_timestamp(sub.max_ts),
          path = CASE WHEN sub.n >= 2 THEN sub.line ELSE NULL END
        FROM (
          WITH target AS (
            SELECT id, track_id, start_index, end_index
            FROM track_segments WHERE id IN (#{ids.join(',')})
          ),
          numbered AS (
            SELECT p.track_id, p.timestamp, p.id, p.lonlat,
                   ROW_NUMBER() OVER (
                     PARTITION BY p.track_id ORDER BY p.timestamp, p.id
                   ) - 1 AS idx
            FROM points p
            WHERE p.track_id IN (SELECT DISTINCT track_id FROM target)
          )
          SELECT t.id, MIN(n.timestamp) AS min_ts, MAX(n.timestamp) AS max_ts,
                 COUNT(*) AS n, ST_MakeLine(n.lonlat::geometry ORDER BY n.timestamp, n.id) AS line
          FROM target t
          JOIN numbered n
            ON n.track_id = t.track_id AND n.idx BETWEEN t.start_index AND t.end_index
          GROUP BY t.id
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
          WITH target AS (
            SELECT id, track_id, start_index, end_index, corrected_at
            FROM track_segments
            WHERE id IN (#{ids.join(',')}) AND start_at IS NULL
          ),
          numbered AS (
            SELECT p.track_id, p.timestamp, p.id,
                   ROW_NUMBER() OVER (
                     PARTITION BY p.track_id ORDER BY p.timestamp, p.id
                   ) - 1 AS idx
            FROM points p
            WHERE p.track_id IN (SELECT DISTINCT track_id FROM target)
          ),
          computed AS (
            SELECT t.id, t.track_id, t.corrected_at, MIN(n.timestamp) AS min_ts
            FROM target t
            JOIN numbered n
              ON n.track_id = t.track_id AND n.idx BETWEEN t.start_index AND t.end_index
            GROUP BY t.id, t.track_id, t.corrected_at
          )
          SELECT c.id,
                 ROW_NUMBER() OVER (
                   PARTITION BY c.track_id, c.min_ts
                   ORDER BY (c.corrected_at IS NOT NULL) DESC, c.id
                 ) AS rn
          FROM computed c
        ) ranked
        WHERE del.id = ranked.id AND ranked.rn > 1 AND del.corrected_at IS NULL
      SQL
    end
  end
end
