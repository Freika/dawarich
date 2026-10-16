defmodule Dawarich.ReleaseMigrations.Effects.LoadDisputedAreas do
  @moduledoc false
  @insert """
  INSERT INTO disputed_areas(name,geom,created_at,updated_at)
  SELECT feature->'properties'->>'name',
    ST_Subdivide(ST_CollectionExtract(ST_MakeValid(ST_SetSRID(ST_GeomFromGeoJSON(feature->>'geometry'),4326)),3),256),
    now(),now()
  FROM jsonb_array_elements($1::text::jsonb->'features') feature
  """
  def run(repo, opts \\ []) do
    content = File.read!(Keyword.get_lazy(opts, :disputed_asset, &asset/0))

    {:ok, :ok} =
      repo.transaction(fn ->
        repo.query!("DELETE FROM disputed_areas", [], log: false)
        repo.query!(@insert, [content], log: false)
        :ok
      end)

    repo.query!("ANALYZE disputed_areas", [], log: false)
    :ok
  end

  def asset, do: Application.app_dir(:dawarich, "priv/disputed_areas.geojson")
end
