defmodule Dawarich.Repo.Migrations.TuneObanJobsAutovacuum do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE oban.oban_jobs SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.02)
    """)
  end

  def down do
    execute(
      "ALTER TABLE oban.oban_jobs RESET (autovacuum_vacuum_scale_factor, autovacuum_analyze_scale_factor)"
    )
  end
end
