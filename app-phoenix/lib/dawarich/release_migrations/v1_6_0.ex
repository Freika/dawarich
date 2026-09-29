defmodule Dawarich.ReleaseMigrations.V1_6_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.6.0"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260328205912", &add_devise_lockable_to_users/1},
      {"20260328210500", &add_two_factor_fields_to_users/1}
    ]
  end

  defp add_devise_lockable_to_users(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "users" ADD "failed_attempts" integer DEFAULT 0 NOT NULL;
    ALTER TABLE "users" ADD "locked_at" timestamp(6);
    ALTER TABLE "users" ADD "unlock_token" character varying;
    CREATE UNIQUE INDEX "index_users_on_unlock_token" ON "users" ("unlock_token");
    """)
  end

  defp add_two_factor_fields_to_users(repo) do
    sql!(repo, ~S"""
    ALTER TABLE "users" ADD "otp_secret" character varying;
    ALTER TABLE "users" ADD "consumed_timestep" integer;
    ALTER TABLE "users" ADD "otp_required_for_login" boolean DEFAULT FALSE NOT NULL;
    ALTER TABLE "users" ADD "otp_backup_codes" text[];
    """)
  end
end
