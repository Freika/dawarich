defmodule Dawarich.PlacesApi.Payload do
  @moduledoc false

  alias Dawarich.{RailsTime, Repo}

  @sources %{0 => "manual", 1 => "photon", 2 => "gpx_waypoint"}
  @keys ~w(id name latitude longitude source note icon color visits_count name_locked created_at tags)
  @tag_keys ~w(id name icon color privacy_radius_meters)
  @tags "SELECT g.taggable_id, t.id, t.name, t.icon, t.color, t.privacy_radius_meters " <>
          "FROM taggings g JOIN tags t ON t.id = g.tag_id " <>
          "WHERE g.taggable_type = 'Place' AND g.taggable_id = ANY($1) ORDER BY g.created_at, g.id"
  @counts "SELECT place_id, count(*) FROM visits WHERE place_id = ANY($1) " <>
            "AND deleted_at IS NULL AND status <> 2 GROUP BY place_id"

  def places(owner, where, params, tail \\ "", repo \\ Repo) do
    rows = repo.query!(select() <> " AND " <> where <> tail, [owner | params]).rows
    ids = Enum.map(rows, &hd/1)

    tags =
      repo.query!(@tags, [ids]).rows
      |> Enum.group_by(&hd/1, fn [_place | tag] -> {:object, Enum.zip(@tag_keys, tag)} end)

    counts = Map.new(repo.query!(@counts, [ids]).rows, &List.to_tuple/1)
    Enum.map(rows, &term(&1, Map.get(tags, hd(&1), []), Map.get(counts, hd(&1), 0)))
  end

  defp select,
    do:
      "SELECT p.id, p.name, COALESCE(ST_Y(p.lonlat::geometry), p.latitude::float8), " <>
        "COALESCE(ST_X(p.lonlat::geometry), p.longitude::float8), p.source, p.note, " <>
        "p.name_locked_at IS NOT NULL, #{RailsTime.sql("p.created_at", 3)} " <>
        "FROM places p WHERE p.user_id = $1"

  defp term([id, name, lat, lon, source, note, locked, created], tags, count) do
    first =
      case tags do
        [{:object, pairs} | _] -> Map.new(pairs)
        [] -> %{}
      end

    {:object,
     Enum.zip(@keys, [
       id,
       name,
       lat,
       lon,
       @sources[source],
       note,
       first["icon"],
       first["color"],
       count,
       locked,
       created,
       tags
     ])}
  end
end
