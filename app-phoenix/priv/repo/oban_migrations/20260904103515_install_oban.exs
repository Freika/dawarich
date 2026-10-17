defmodule Dawarich.Repo.Migrations.InstallOban do
  use Ecto.Migration

  def up, do: Oban.Migration.up(prefix: "oban", create_schema: false)
  def down, do: Oban.Migration.down(prefix: "oban")
end
