defmodule Dawarich.Repo.Migrations.AddBackfillScheduleMarker do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE phoenix.track_backfill_ranges ADD COLUMN IF NOT EXISTS scheduled boolean NOT NULL DEFAULT true"
    )
  end

  def down do
    execute("ALTER TABLE phoenix.track_backfill_ranges DROP COLUMN IF EXISTS scheduled")
  end
end
