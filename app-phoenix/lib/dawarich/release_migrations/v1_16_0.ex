defmodule Dawarich.ReleaseMigrations.V1_16_0 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration
  import Dawarich.ReleaseMigration
  alias Dawarich.ReleaseMigrations.Effects

  def release, do: "1.16.0"
  def data_versions, do: []

  def steps do
    [
      {"20261014120000", &create_disputed_areas/1},
      {"20261014120100", &load_disputed_areas/1, transaction: false}
    ]
  end

  defp create_disputed_areas(repo) do
    unless table?(repo, "disputed_areas") do
      sql!(
        repo,
        "CREATE TABLE disputed_areas (id bigserial PRIMARY KEY, name character varying NOT NULL, geom geometry(Geometry,4326) NOT NULL, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL)"
      )

      sql!(repo, "CREATE INDEX index_disputed_areas_on_geom ON disputed_areas USING gist (geom)")
    end

    :ok
  end

  defp load_disputed_areas(repo) do
    Effects.LoadDisputedAreas.run(repo)

    repo.query!(
      "DELETE FROM regions WHERE code=ANY($1::varchar[])",
      [Dawarich.Achievements.Registry.disputed_subdivisions()],
      log: false
    )

    {:jobs, [job("DataMigrations::BackfillAchievementsJob")]}
  end
end
