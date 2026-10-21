defmodule Dawarich.ReleaseMigrations.Effects.LoadRegions do
  @moduledoc false

  @upsert """
  INSERT INTO regions (code, geom, created_at, updated_at)
  SELECT feature -> 'properties' ->> 'iso_3166_2',
         ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON(feature ->> 'geometry'), 4326)),
         NOW(), NOW()
  FROM jsonb_array_elements($1::text::jsonb -> 'features') AS feature
  WHERE NOT (feature -> 'properties' ->> 'iso_3166_2') = ANY($3::varchar[])
  ON CONFLICT (code) DO UPDATE SET geom = EXCLUDED.geom, updated_at = EXCLUDED.updated_at
  """

  @repair """
  UPDATE regions
  SET geom = ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
  WHERE NOT ST_IsValid(geom)
  """

  def run(repo, opts \\ []) do
    content = File.read!(Keyword.get_lazy(opts, :asset, &asset/0))

    disputed = Dawarich.Achievements.Registry.disputed_subdivisions()

    {sql, params} =
      case Keyword.fetch(opts, :now) do
        {:ok, now} ->
          {String.replace(@upsert, "NOW()", "$2::timestamp"), [content, now, disputed]}

        :error ->
          {String.replace(@upsert, "$3", "$2"), [content, disputed]}
      end

    repo.query!(sql, params, log: false)
    repo.query!("DELETE FROM regions WHERE code=ANY($1::varchar[])", [disputed], log: false)
    repo.query!(@repair, [], log: false)
    :ok
  end

  def asset, do: Application.app_dir(:dawarich, "priv/admin1_world.geojson")
end
