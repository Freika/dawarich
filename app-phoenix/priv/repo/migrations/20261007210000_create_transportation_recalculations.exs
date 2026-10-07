defmodule Dawarich.Repo.Migrations.CreateTransportationRecalculations do
  use Ecto.Migration

  def change do
    create table(:transportation_recalculations, prefix: "phoenix", primary_key: false) do
      add :user_id, :bigint, primary_key: true

      add :event_id, :uuid, null: false
      add :remaining, :integer
    end
  end
end
