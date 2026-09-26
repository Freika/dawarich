defmodule Dawarich.ReleaseMigrations.Effects.LoadRegions do
  @moduledoc false

  @upsert """
  INSERT INTO regions (code, geom, created_at, updated_at)
  SELECT feature -> 'properties' ->> 'iso_3166_2',
         ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)),
         NOW(), NOW()
  FROM jsonb_array_elements($1::text::jsonb -> 'features') AS feature
  ON CONFLICT (code) DO UPDATE SET geom = EXCLUDED.geom, updated_at = EXCLUDED.updated_at
  """

  @repair """
  UPDATE regions
  SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
  WHERE NOT ST_IsValid(geom)
  """

  def run(repo) do
    repo.query!(@upsert, [File.read!(asset())], log: false)
    repo.query!(@repair, [], log: false)
    :ok
  end

  def asset, do: Application.app_dir(:dawarich, "priv/admin1_world.geojson")
end
