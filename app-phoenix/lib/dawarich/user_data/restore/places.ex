defmodule Dawarich.UserData.Restore.Places do
  @moduledoc false
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Imports.NormalCast.Text
  alias Dawarich.UserData.Restore.Batch

  def call(repo, user, data, context) do
    if Enumerable.impl_for(data) do
      repo.checkout(fn ->
        context = Batch.with_column_types(repo, "places", context)

        Enum.reduce(data, 0, fn
          row, count when is_map(row) -> count + restore_checked(repo, user, row, context)
          _, count -> count
        end)
      end)
    else
      0
    end
  end

  def find(repo, user, name, lat, lon) do
    repo.query!(
      "SELECT id FROM places WHERE user_id=$1 AND name=$2 AND latitude=$3::numeric(10,6) AND longitude=$4::numeric(10,6) ORDER BY id LIMIT 1",
      [user, Text.cast(name), number(lat), number(lon)],
      log: false,
      cache_statement: "restore_place_identity"
    ).rows
  end

  def coordinates(data, lat_key \\ "latitude", lon_key \\ "longitude") do
    lat = data[lat_key]
    lon = data[lon_key]
    if lat != nil and lon != nil, do: {Ruby.to_f(lat), Ruby.to_f(lon)}
  end

  defp restore_checked(repo, user, row, context) do
    with true <- Ruby.present?(row["name"]),
         {lat, lon} <- coordinates(row),
         [] <- find(repo, user, row["name"], lat, lon) do
      restore(repo, user, row, context)
    else
      _ -> 0
    end
  end

  defp restore(repo, user, row, context) do
    name = row["name"]

    with true <- Ruby.present?(name),
         {lat, lon} <- coordinates(row) do
      if length(String.codepoints(Text.cast(name))) > 255 do
        0
      else
        row
        |> lock_name(context)
        |> owned_import(repo, user, context)
        |> Map.drop(
          ~w(created_at updated_at latitude longitude user user_id machine_named user_named)
        )
        |> Map.merge(%{
          "user_id" => user,
          "latitude" => lat,
          "longitude" => lon,
          "lonlat" => "SRID=4326;POINT(#{coordinate(lon)} #{coordinate(lat)})",
          "created_at" => context.now,
          "updated_at" => context.now
        })
        |> then(&Batch.create!(repo, "places", &1, context))
      end
    else
      _ -> 0
    end
  end

  defp lock_name(row, context) do
    cond do
      Ruby.truthy?(row["machine_named"]) -> row
      Text.cast(row["name"]) == "Suggested place" -> Map.put(row, "name_locked_at", nil)
      Ruby.truthy?(row["user_named"]) -> Map.put(row, "name_locked_at", context.now)
      true -> row
    end
  end

  defp owned_import(row, _repo, _user, _context) when not is_map_key(row, "import_id"),
    do: row

  defp owned_import(row, repo, user, context) do
    id = Batch.row!(repo, "places", Map.take(row, ["import_id"]), context)["import_id"]

    case repo.query!("SELECT id FROM imports WHERE id=$1 AND user_id=$2", [id, user], log: false).rows do
      [[id]] -> Map.put(row, "import_id", id)
      [] -> Map.delete(row, "import_id")
    end
  end

  defp number(value), do: Decimal.from_float(value)

  defp coordinate(value),
    do: value |> Dawarich.Ingest.Cast.decimal({10, 6}) |> Decimal.to_string(:normal)
end
