defmodule Dawarich.ReleaseMigrations.V1_14_2 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.14.2"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260828090000", &add_access_until_to_families/1},
      {"20260828100000", &enqueue_families_backfill/1},
      {"20260831120000", &enqueue_family_member_entitlements_backfill/1},
      {"20260901120000", &remove_retired_max_gap_minutes_in_city_setting/1}
    ]
  end

  defp add_access_until_to_families(repo) do
    unless column?(repo, "families", "access_until") do
      sql!(repo, ~S"""
      ALTER TABLE "families" ADD "access_until" timestamp(6);
      """)
    end
  end

  defp enqueue_families_backfill(_repo),
    do: {:jobs, [job("DataMigrations::BackfillFamiliesForFamilyPlanJob")]}

  defp enqueue_family_member_entitlements_backfill(_repo),
    do: {:jobs, [job("DataMigrations::BackfillFamilyMemberEntitlementsJob")]}

  defp remove_retired_max_gap_minutes_in_city_setting(repo) do
    sql!(repo, ~S"""
    UPDATE users SET settings = settings - 'max_gap_minutes_in_city' WHERE settings ?| array['max_gap_minutes_in_city'];
    """)
  end
end
