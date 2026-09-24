defmodule Dawarich.Repo.Migrations.InstallOban do
  use Ecto.Migration

  def up, do: Oban.Migration.up(prefix: "oban")
  def down, do: Oban.Migration.down(prefix: "oban")
end
