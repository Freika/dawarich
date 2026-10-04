defmodule Dawarich.Repo.Migrations.AddTrackBackfillLegacyAdoption do
  use Ecto.Migration

  def up,
    do:
      execute(
        "ALTER TABLE phoenix.track_backfill_walks ADD COLUMN IF NOT EXISTS legacy_cursor_pending boolean NOT NULL DEFAULT false"
      )

  def down,
    do: execute("ALTER TABLE phoenix.track_backfill_walks DROP COLUMN legacy_cursor_pending")
end
