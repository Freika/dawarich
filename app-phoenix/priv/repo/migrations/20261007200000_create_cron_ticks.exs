defmodule Dawarich.Repo.Migrations.CreateCronTicks do
  use Ecto.Migration

  def change do
    create table(:cron_ticks, prefix: "phoenix", primary_key: false) do
      add :key, :text, primary_key: true
      add :tick, :utc_datetime_usec, primary_key: true
    end
  end
end
