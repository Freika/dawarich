defmodule Dawarich.Repo.Migrations.CreateTrackBackfillState do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS phoenix.track_backfill_ranges (
      user_id bigint NOT NULL PRIMARY KEY,
      earliest_timestamp bigint NOT NULL,
      latest_timestamp bigint NOT NULL,
      cycle_id uuid NOT NULL,
      time_zone text NOT NULL,
      due_at timestamptz NOT NULL,
      expires_at timestamptz NOT NULL,
      inserted_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CHECK (earliest_timestamp <= latest_timestamp)
    )
    """)

    execute("""
    CREATE TABLE IF NOT EXISTS phoenix.track_backfill_walks (
      user_id bigint NOT NULL PRIMARY KEY,
      walk_id uuid NOT NULL,
      cursor_timestamp bigint,
      step_event_id uuid,
      selected_start_timestamp bigint,
      selected_end_timestamp bigint,
      state text NOT NULL,
      expires_at timestamptz NOT NULL,
      time_zone text NOT NULL,
      inserted_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CHECK (state IN ('walking', 'backoff')),
      CHECK ((step_event_id IS NULL AND selected_start_timestamp IS NULL AND selected_end_timestamp IS NULL)
        OR (step_event_id IS NOT NULL AND selected_start_timestamp IS NOT NULL AND selected_end_timestamp IS NOT NULL))
    )
    """)

    for table <- ~w(track_backfill_ranges track_backfill_walks) do
      execute(
        "CREATE INDEX IF NOT EXISTS #{table}_expires_at_index ON phoenix.#{table} (expires_at)"
      )
    end
  end

  def down, do: execute("DROP TABLE phoenix.track_backfill_ranges, phoenix.track_backfill_walks")
end
