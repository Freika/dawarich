defmodule Dawarich.VisitsApi.SelectPlace do
  @moduledoc false

  alias Dawarich.{Geocoding, Jobs, RailsTime}
  alias Dawarich.VisitsApi.Effects
  alias Dawarich.PlacesApi.Payload
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def call(owner, id, attrs, zone, now, repo \\ Jobs.repo()) do
    RailsTime.with_zone(repo, zone, fn ->
      with {:ok, old} <- Effects.load(repo, owner, id),
           {:ok, attrs} <- input(attrs) do
        ident =
          if Ruby.present?(attrs["osm_id"]),
            do: Ruby.to_s(attrs["osm_id"]),
            else: Enum.map_join(~w(name latitude longitude), ":", &Ruby.to_s(attrs[&1]))

        repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [
          "select_place:#{owner}:#{ident}"
        ])

        stamp = DateTime.to_naive(now)
        place = find(repo, owner, attrs) || create(repo, owner, attrs, stamp)

        repo.query!(
          "UPDATE places SET name_locked_at=$2,updated_at=$2 WHERE id=$1 AND name_locked_at IS NULL",
          [place, stamp]
        )

        repo.query!("UPDATE visits SET place_id=$2,name=$3,status=1,updated_at=$4 WHERE id=$1", [
          id,
          place,
          attrs["name"],
          stamp
        ])

        {:ok, new} = Effects.load(repo, owner, id)
        Effects.changed(repo, old, new, stamp, old.place_id != new.place_id)
        [{:object, fields}] = Payload.places(owner, "p.id=$2", [place], "", repo)
        {:ok, {:object, List.keydelete(fields, "name_locked", 0)}}
      end
    end)
  end

  defp input(attrs) when is_map(attrs) do
    missing = Enum.find(~w(name latitude longitude), &Ruby.blank?(attrs[&1]))

    cond do
      missing ->
        missing(missing)

      !Enum.all?(Map.take(attrs, ~w(name latitude longitude osm_id)), fn {_, v} ->
        is_nil(v) || is_binary(v) || is_number(v)
      end) ->
        {:replay, "photon attribute shape"}

      !is_nil(attrs["geodata"]) && !is_map(attrs["geodata"]) ->
        {:replay, "photon geodata shape"}

      true ->
        lat = number(attrs["latitude"])
        lon = number(attrs["longitude"])

        cond do
          lat < -90 || lat > 90 ->
            missing("latitude")

          lon < -180 || lon > 180 ->
            missing("longitude")

          true ->
            {:ok,
             attrs
             |> Map.put("name", Ruby.to_s(attrs["name"]))
             |> Map.put("latitude", lat)
             |> Map.put("longitude", lon)}
        end
    end
  end

  defp input(_), do: {:replay, "photon root shape"}
  defp number(value) when is_number(value), do: value * 1.0
  defp number(value), do: Ruby.to_f(value)

  defp missing(key),
    do: {:error, 422, "param is missing or the value is empty or invalid: " <> key}

  defp find(repo, owner, attrs) do
    case repo.query!(
           "SELECT id FROM places WHERE user_id=$1 AND name=$2 AND ST_DWithin(lonlat::geography,ST_SetSRID(ST_MakePoint($3,$4),4326)::geography,50) ORDER BY id LIMIT 1",
           [owner, attrs["name"], attrs["longitude"], attrs["latitude"]]
         ).rows do
      [[id]] -> id
      [] -> nil
    end
  end

  defp create(repo, owner, attrs, now) do
    data = if Geocoding.Config.resolve(repo).store_geodata, do: attrs["geodata"] || %{}, else: %{}
    lock = if attrs["name"] == "Suggested place", do: nil, else: now

    [[id]] =
      repo.query!(
        "INSERT INTO places (user_id,name,latitude,longitude,lonlat,city,country,geodata,source,name_locked_at,created_at,updated_at) VALUES ($1,$2,$3::double precision,$4::double precision,ST_SetSRID(ST_MakePoint($4::double precision,$3::double precision),4326),$5,$6,$7,1,$8,$9,$9) RETURNING id",
        [
          owner,
          attrs["name"],
          attrs["latitude"],
          attrs["longitude"],
          attrs["city"],
          attrs["country"],
          data,
          lock,
          now
        ]
      ).rows

    id
  end
end
