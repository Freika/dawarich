defmodule Dawarich.Places.Reads do
  @moduledoc false
  alias Dawarich.{PlaceDrawer, PlaceList}

  def list(scope, page, repo) when is_binary(page) or is_nil(page) do
    if byte_size(page || "") <= 128 and Dawarich.RubyInteger.to_i(page) <= 1_000_000_000_000_000 do
      case PlaceList.load(scope.user, page, repo: repo) do
        :rails -> {:error, :unsupported}
        result -> result
      end
    else
      {:error, :invalid_input}
    end
  end

  def list(_, _, _), do: {:error, :invalid_input}
  def detail(scope, id, repo), do: PlaceDrawer.load(scope.user, id, repo, :native)

  def edit(scope, id, repo) do
    case repo.query!(
           "SELECT name,latitude::float8,longitude::float8,source,note,name_locked_at IS NOT NULL,demo,COALESCE(ST_X(lonlat::geometry)=longitude::float8 AND ST_Y(lonlat::geometry)=latitude::float8,false) FROM places WHERE id=$1 AND user_id=$2",
           [id, scope.user.id],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [[name, lat, lon, source, note, locked, demo, true]]
      when source in 0..2 or is_nil(source) ->
        selected =
          repo.query!(
            "SELECT t.id FROM taggings g JOIN tags t ON t.id=g.tag_id WHERE g.taggable_type='Place' AND g.taggable_id=$1 AND t.user_id=$2 ORDER BY g.created_at,g.id",
            [id, scope.user.id],
            log: false
          ).rows
          |> List.flatten()

        {:ok,
         %{
           id: id,
           name: name,
           latitude: lat,
           longitude: lon,
           source: if(source != nil, do: Enum.at(~w(manual photon gpx_waypoint), source)),
           note: note,
           locked: locked,
           demo: demo,
           tag_ids: selected,
           tags: tags(scope, repo)
         }}

      _ ->
        {:error, :unsupported}
    end
  end

  def tags(scope, repo) do
    repo.query!(
      "SELECT id,name,icon,color FROM tags WHERE user_id=$1 ORDER BY name,id",
      [scope.user.id],
      log: false
    ).rows
    |> Enum.map(fn [id, name, icon, color] -> %{id: id, name: name, icon: icon, color: color} end)
  end
end
