# frozen_string_literal: true

# Change capture for the points rewrite: a row-level trigger on v1 `points`
# logs every write while the multi-hour copy walks, and drain! re-transforms
# the touched rows into points_v2. Self-hosted entrypoints never pause
# Sidekiq for migrations, so the copy MUST tolerate live writes; the final
# zero-delta drain runs inside the swap's ACCESS EXCLUSIVE transaction.
module Points
  module Rewrite
    class ChangeCapture
      DRAIN_BATCH = 10_000

      def initialize(connection = ActiveRecord::Base.connection)
        @connection = connection
      end

      attr_reader :connection

      LOCK_TIMEOUT = '2s'
      INSTALL_ATTEMPTS = 3

      # CREATE TRIGGER needs SHARE ROW EXCLUSIVE on the live table; bounded by
      # lock_timeout and retried so a long import batch cannot queue every
      # other writer behind this DDL.
      def install
        return if installed?

        attempts = 0
        begin
          attempts += 1
          connection.transaction do
            connection.execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
            connection.execute(install_sql)
          end
        rescue ActiveRecord::LockWaitTimeout
          raise if attempts >= INSTALL_ATTEMPTS

          sleep(attempts)
          retry
        end
      end

      def install_sql
        <<~SQL
          CREATE TABLE IF NOT EXISTS points_v2_changes (
            id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            point_id bigint NOT NULL,
            op char(1) NOT NULL
          );
          CREATE OR REPLACE FUNCTION points_v2_capture() RETURNS trigger AS $$
          BEGIN
            INSERT INTO points_v2_changes (point_id, op)
            VALUES (COALESCE(NEW.id, OLD.id), left(TG_OP, 1));
            RETURN NULL;
          END;
          $$ LANGUAGE plpgsql;
          CREATE TRIGGER points_v2_capture
            AFTER INSERT OR UPDATE OR DELETE ON points
            FOR EACH ROW EXECUTE FUNCTION points_v2_capture();
        SQL
      end

      def installed?
        connection.select_value(
          "SELECT COUNT(*) FROM pg_trigger WHERE tgname = 'points_v2_capture'"
        ).to_i.positive?
      end

      def pending_count
        return 0 unless connection.table_exists?('points_v2_changes')

        connection.select_value('SELECT COUNT(*) FROM points_v2_changes').to_i
      end

      # Applies one batch of logged changes; returns the number of log rows
      # consumed (0 = drained). Re-transforming by id covers INSERT and
      # UPDATE; ids gone from points are deleted from v2. A NULL-timestamp
      # row changed mid-copy keeps its already-synthesized v2 row: a
      # geocoding stamp on an invisible legacy point is acceptably lost.
      # One transaction consumes exactly the log rows it applies: DELETE ...
      # RETURNING only ever hands back committed rows, so a writer whose log
      # entry commits mid-batch keeps it for the next batch instead of losing it.
      def drain_batch(limit = DRAIN_BATCH)
        consumed = 0
        connection.transaction do
          point_ids = connection.execute(<<~SQL).values.flatten
            DELETE FROM points_v2_changes
            WHERE id IN (SELECT id FROM points_v2_changes ORDER BY id LIMIT #{limit.to_i})
            RETURNING point_id
          SQL
          consumed = point_ids.size
          next if consumed.zero?

          ids_sql = point_ids.map(&:to_i).uniq.join(', ')
          connection.execute(Sql.transform_upsert(where: "p.id IN (#{ids_sql})"))
          connection.execute(<<~SQL)
            DELETE FROM points_v2
            WHERE id IN (#{ids_sql})
              AND NOT EXISTS (SELECT 1 FROM points p WHERE p.id = points_v2.id)
          SQL
        end
        consumed
      end

      def drain_fully
        loop { break if drain_batch.zero? }
      end

      def drop
        connection.execute(<<~SQL)
          DROP TRIGGER IF EXISTS points_v2_capture ON points;
          DROP FUNCTION IF EXISTS points_v2_capture();
          DROP TABLE IF EXISTS points_v2_changes;
        SQL
      end
    end
  end
end
