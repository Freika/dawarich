defmodule Dawarich.Repo.Migrations.CreateDigestExecutions do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE phoenix.digest_executions (
      effect text NOT NULL CHECK (effect IN ('digests.calculate_month','digests.calculate_year')),
      user_id bigint NOT NULL,
      year integer NOT NULL,
      month integer NOT NULL CHECK (month BETWEEN 0 AND 12),
      state text NOT NULL CHECK (state IN ('claimed','generated','published')),
      outcome text CHECK (outcome IN ('mail','missing')),
      legacy boolean NOT NULL DEFAULT false,
      updated_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (effect,user_id,year,month),
      CHECK ((effect='digests.calculate_year' AND month=0) OR
             (effect='digests.calculate_month' AND month BETWEEN 1 AND 12)),
      CHECK (state='claimed' OR outcome IS NOT NULL)
    )
    """)

    flush()
    Dawarich.Digests.ExecutionUpgrade.backfill(repo())
  end

  def down, do: execute("DROP TABLE phoenix.digest_executions")
end
