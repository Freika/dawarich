defmodule Dawarich.Seeds.Countries do
  @moduledoc false

  def asset_path(opts \\ []) do
    priv = Keyword.get_lazy(opts, :priv_dir, fn -> Application.app_dir(:dawarich, "priv") end)
    Path.join(priv, "countries.geojson.gz")
  end

  def run(repo, opts \\ []) do
    if repo.query!("SELECT NOT EXISTS (SELECT 1 FROM countries)", [], log: false).rows == [[true]] do
      source = opts |> asset_path() |> File.read!() |> :zlib.gunzip() |> Jason.decode!()

      {:ok, :ok} =
        repo.transaction(fn ->
          Enum.each(Map.fetch!(source, "features"), &insert!(repo, &1, opts))
        end)
    end

    :ok
  end

  defp insert!(repo, feature, opts) do
    properties = Map.fetch!(feature, "properties")
    name = required!(properties["name"], "Name")
    iso_a2 = required!(properties["ISO3166-1-Alpha-2"], "Iso a2")
    iso_a3 = required!(properties["ISO3166-1-Alpha-3"], "Iso a3")
    geometry = Map.get(feature, "geometry")

    unless is_map(geometry) and geometry["type"] in ["Polygon", "MultiPolygon"] and
             is_list(geometry["coordinates"]) and geometry["coordinates"] != [],
           do: raise(ArgumentError, "Validation failed: Geom can't be blank")

    now = Keyword.get_lazy(opts, :now, &NaiveDateTime.utc_now/0)

    repo.query!(
      "INSERT INTO countries (name,iso_a2,iso_a3,geom,created_at,updated_at) VALUES ($1,$2,$3,ST_Multi(ST_SetSRID(ST_GeomFromGeoJSON($4),4326)),$5,$5)",
      [name, iso_a2, iso_a3, Jason.encode!(geometry), now],
      log: false
    )
  end

  defp required!(value, field) do
    if is_binary(value) and String.trim(value) != "",
      do: value,
      else: raise(ArgumentError, "Validation failed: #{field} can't be blank")
  end
end
