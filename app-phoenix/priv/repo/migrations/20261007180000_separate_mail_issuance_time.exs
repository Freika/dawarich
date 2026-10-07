defmodule Dawarich.Repo.Migrations.SeparateMailIssuanceTime do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE phoenix.delivery_claims ADD COLUMN issued_at timestamptz")
    execute("UPDATE phoenix.delivery_claims SET issued_at=claimed_at")

    execute(
      "ALTER TABLE phoenix.delivery_claims ALTER COLUMN issued_at SET DEFAULT now(), ALTER COLUMN issued_at SET NOT NULL"
    )
  end

  def down do
    execute("ALTER TABLE phoenix.delivery_claims DROP COLUMN issued_at")
  end
end
