defmodule Dawarich.Repo.Migrations.ArchiveContinuationIdentity do
  use Ecto.Migration

  def up do
    execute("""
    WITH chains AS (
      SELECT args->>'user_id' AS user_id, max(id) AS keeper,
             max((args->>'cursor')::bigint) AS cursor,
             min(coalesce(args->>'coverage_floor', args->>'cursor')::bigint) AS floor
      FROM oban.oban_jobs
      WHERE worker = 'Dawarich.RawData.ArchiveWorker'
        AND state IN ('available','scheduled','executing','retryable')
        AND args->>'user_id' ~ '^-?[0-9]+$' AND args->>'cursor' ~ '^-?[0-9]+$'
      GROUP BY args->>'user_id'
    )
    UPDATE oban.oban_jobs j SET
      state = CASE WHEN j.id = c.keeper THEN j.state ELSE 'cancelled'::oban.oban_job_state END,
      cancelled_at = CASE WHEN j.id = c.keeper THEN j.cancelled_at ELSE now() END,
      args = CASE WHEN j.id = c.keeper THEN
        (j.args - 'coverage_floor') || jsonb_build_object('cursor', c.cursor) ||
        CASE WHEN c.floor < c.cursor THEN jsonb_build_object('coverage_floor', c.floor) ELSE '{}'::jsonb END
        ELSE j.args END
    FROM chains c WHERE j.args->>'user_id' = c.user_id
      AND j.worker = 'Dawarich.RawData.ArchiveWorker'
      AND j.state IN ('available','scheduled','executing','retryable')
    """)

    execute("""
    CREATE OR REPLACE FUNCTION oban.archive_continuation_identity() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE
      high_cursor bigint;
      low_cursor bigint;
      proposed_cursor bigint;
      proposed_floor bigint;
      parent_id bigint;
    BEGIN
      IF NEW.worker <> 'Dawarich.RawData.ArchiveWorker'
        OR NEW.state NOT IN ('available','scheduled','executing','retryable')
        OR (NEW.args->>'user_id' ~ '^-?[0-9]+$' AND NEW.args->>'cursor' ~ '^-?[0-9]+$') IS DISTINCT FROM true
      THEN RETURN NEW; END IF;

      PERFORM pg_advisory_xact_lock(hashtextextended('archive_continuation:' || (NEW.args->>'user_id'), 0));
      proposed_cursor := (NEW.args->>'cursor')::bigint;
      proposed_floor := coalesce(NEW.args->>'coverage_floor', NEW.args->>'cursor')::bigint;
      parent_id := (NEW.meta->>'archive_parent_id')::bigint;

      SELECT max((args->>'cursor')::bigint),
             min(coalesce(args->>'coverage_floor', args->>'cursor')::bigint)
      INTO high_cursor, low_cursor
      FROM oban.oban_jobs
      WHERE worker = NEW.worker AND args->>'user_id' = NEW.args->>'user_id'
        AND state IN ('available','scheduled','executing','retryable')
        AND id <> NEW.id AND (parent_id IS NULL OR id <> parent_id);

      high_cursor := greatest(proposed_cursor, high_cursor);
      low_cursor := least(proposed_floor, low_cursor);
      NEW.args := (NEW.args - 'coverage_floor') || jsonb_build_object('cursor', high_cursor);
      IF low_cursor < high_cursor THEN
        NEW.args := NEW.args || jsonb_build_object('coverage_floor', low_cursor);
      END IF;

      UPDATE oban.oban_jobs SET state = 'cancelled', cancelled_at = now()
      WHERE worker = NEW.worker AND args->>'user_id' = NEW.args->>'user_id'
        AND state IN ('available','scheduled','executing','retryable') AND id <> NEW.id;
      RETURN NEW;
    END $$
    """)

    execute("DROP TRIGGER IF EXISTS archive_continuation_identity ON oban.oban_jobs")

    execute("""
    CREATE TRIGGER archive_continuation_identity BEFORE INSERT OR UPDATE OF state, args
    ON oban.oban_jobs FOR EACH ROW EXECUTE FUNCTION oban.archive_continuation_identity()
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS archive_continuation_identity ON oban.oban_jobs ((args->>'user_id'))
    WHERE worker = 'Dawarich.RawData.ArchiveWorker'
      AND state IN ('available','scheduled','executing','retryable')
      AND args->>'user_id' ~ '^-?[0-9]+$' AND args->>'cursor' ~ '^-?[0-9]+$'
    """)
  end

  def down do
    execute("DROP INDEX oban.archive_continuation_identity")
    execute("DROP TRIGGER archive_continuation_identity ON oban.oban_jobs")
    execute("DROP FUNCTION oban.archive_continuation_identity()")
  end
end
