defmodule Dawarich.ReleaseMigrations.Effects.ReloadBundledCountryBoundaries do
  @moduledoc false
  import Dawarich.ReleaseMigration

  def run(repo) do
    if exists?(repo, "SELECT 1 FROM countries") do
      source =
        Dawarich.Seeds.Countries.asset_path() |> File.read!() |> :zlib.gunzip() |> Jason.decode!()

      {:ok, :ok} =
        repo.transaction(fn ->
          for feature <- source["features"],
              code = feature["properties"]["ISO3166-1-Alpha-2"],
              code in ["UA", "RU"] do
            repo.query!(
              "UPDATE countries SET geom=ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON($1),4326)),updated_at=now() WHERE iso_a2=$2",
              [Jason.encode!(feature["geometry"]), code],
              log: false
            )
          end

          :ok
        end)

      Dawarich.Redis.cache_command(["DEL", "dawarich/countries_codes"])
      {:jobs, [job("DataMigrations::ReassignBoundaryPointsJob")]}
    else
      :ok
    end
  end
end
