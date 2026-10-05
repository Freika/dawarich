defmodule Dawarich.UserData.Restore.Places do
  @moduledoc false
  alias Dawarich.Ingest.Ruby
  alias Dawarich.Imports.NormalCast.Text
  alias Dawarich.UserData.Restore.Batch

  def call(repo, user, data, context) do
    if Enumerable.impl_for(data) do
      context = Batch.with_column_types(repo, "places", context)

      data
      |> Stream.filter(&is_map/1)
      |> Stream.chunk_every(5000)
      |> Enum.reduce(0, fn batch, total ->
        candidates = candidates(batch)
        existing = existing(repo, user, Enum.reject(candidates, &(elem(&1, 1) == :deferred)))

        {count, _seen} =
          Enum.reduce(candidates, {total, existing}, fn
            {row, :deferred}, {count, seen} ->
              {count + restore_checked(repo, user, row, context), seen}

            {row, key}, {count, seen} ->
              if MapSet.member?(seen, key) do
                {count, seen}
              else
                inserted = restore(repo, user, row, context)
                seen = if inserted == 1, do: MapSet.put(seen, stored_identity(row)), else: seen
                {count + inserted, seen}
              end
          end)

        count
      end)
    else
      0
    end
  end

  def find(repo, user, name, lat, lon) do
    repo.query!(
      "SELECT id FROM places WHERE user_id=$1 AND name=$2 AND latitude=$3::numeric(10,6) AND longitude=$4::numeric(10,6) ORDER BY id LIMIT 1",
      [user, Text.cast(name), number(lat), number(lon)],
      log: false
    ).rows
  end

  def coordinates(data, lat_key \\ "latitude", lon_key \\ "longitude") do
    lat = data[lat_key]
    lon = data[lon_key]
    if lat != nil and lon != nil, do: {Ruby.to_f(lat), Ruby.to_f(lon)}
  end

  defp candidates(batch) do
    Enum.flat_map(batch, &candidate/1)
  end

  defp candidate(row) do
    with true <- Ruby.present?(row["name"]),
         {lat, lon} <- coordinates(row) do
      lat = lookup_coordinate(lat)
      lon = lookup_coordinate(lon)

      if Enum.all?([lat, lon], &(Decimal.compare(Decimal.abs(Decimal.new(&1)), 10_000) == :lt)),
        do: [{row, {Text.cast(row["name"]), lat, lon}}],
        else: [{row, :deferred}]
    else
      _ -> []
    end
  rescue
    _ -> [{row, :deferred}]
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

  defp stored_identity(row) do
    {lat, lon} = coordinates(row)

    {Text.cast(row["name"]), lat |> Dawarich.Ingest.Cast.decimal({10, 6}) |> numeric_key(),
     lon |> Dawarich.Ingest.Cast.decimal({10, 6}) |> numeric_key()}
  end

  defp lookup_coordinate(value),
    do: value |> number() |> Decimal.round(6, :half_up) |> numeric_key()

  defp numeric_key(value) do
    if Decimal.equal?(value, 0),
      do: "0",
      else: value |> Decimal.normalize() |> Decimal.to_string(:normal)
  end

  defp existing(_repo, _user, []), do: MapSet.new()

  defp existing(repo, user, candidates) do
    keys = Enum.map(candidates, &elem(&1, 1)) |> List.to_tuple()

    rows =
      candidates
      |> Enum.with_index()
      |> Enum.map(fn {{_, {name, lat, lon}}, i} ->
        %{ordinal: i, name: name, latitude: lat, longitude: lon}
      end)

    repo.query!(
      "SELECT r.ordinal FROM jsonb_to_recordset($2::jsonb) AS r(ordinal int,name text,latitude numeric(10,6),longitude numeric(10,6)) WHERE EXISTS (SELECT 1 FROM places p WHERE p.user_id=$1 AND p.name=r.name AND p.latitude=r.latitude AND p.longitude=r.longitude)",
      [user, rows],
      log: false
    ).rows
    |> MapSet.new(fn [i] -> elem(keys, i) end)
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
