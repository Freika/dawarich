defmodule Dawarich.ReleaseMigrations.V1_3_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.3.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260301201446", &add_plan_to_users/1},
      {"20260301202147", &set_plan_for_existing_users/1}
    ]
  end

  defp add_plan_to_users(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "users" ADD "plan" integer DEFAULT 1 NOT NULL;
    CREATE INDEX "index_users_on_plan" ON "users" ("plan");
    """)
  end

  defp set_plan_for_existing_users(repo) do
    if self_hosted?() do
      sql!(repo, "UPDATE users SET plan = 1")
    else
      sql!(repo, "UPDATE users SET plan = 1 WHERE status IN (1, 2)")
      sql!(repo, "UPDATE users SET plan = 0 WHERE status = 0")
    end
  end
end
