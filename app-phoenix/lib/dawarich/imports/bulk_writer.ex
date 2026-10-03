defmodule Dawarich.Imports.BulkWriter do
  @moduledoc false

  alias Dawarich.Imports.{NormalCast, SourceDimensions}
  alias Dawarich.Imports.Geometry
  alias Dawarich.{RailsCommands, Repo}

  @columns ~w(lonlat timestamp altitude altitude_decimal velocity tracker_id import_id user_id created_at updated_at battery ping accuracy vertical_accuracy ssid bssid inrids in_regions topic battery_status connection trigger motion_data raw_data course course_accuracy)a
  @required ~w(lonlat timestamp import_id user_id created_at updated_at)a
  @limit 1_000

  def write(batch, import, cache \\ %{}, repo \\ Repo, fence \\ fn fun -> fun.() end)
      when is_list(batch) do
    if length(batch) > @limit, do: raise(ArgumentError, "normal import batch exceeds 1000 rows")
    rows = Enum.reject(batch, &is_nil/1)
    fence.(fn -> validate!(rows, import, repo) end)

    unique =
      rows
      |> Enum.reject(&Geometry.null_island?(&1.lonlat))
      |> Enum.uniq_by(&{&1.lonlat, &1.timestamp, &1.user_id})

    if unique == [] do
      {0, cache}
    else
      {values, cache} = stamp(unique, cache, repo, fence)
      inserted = fence.(fn -> insert!(values, repo) end)
      fence.(fn -> counters!(length(unique), length(unique) - inserted, import, repo) end)

      if inserted > 0 do
        fence.(fn ->
          RailsCommands.insert!(repo, "points.tile_epoch", %{
            "user_id" => import.user_id,
            "timestamps" => Enum.map(unique, & &1.timestamp)
          })
        end)
      end

      {inserted, cache}
    end
  end

  defp validate!([], _import, _repo), do: :ok

  defp validate!(rows, %{id: id, user_id: user}, repo) do
    keys = rows |> hd() |> Map.keys() |> Enum.sort()

    unless @required -- keys == [] and keys -- @columns == [] and
             Enum.all?(rows, fn row ->
               Map.keys(row) |> Enum.sort() == keys and row.import_id == id and
                 row.user_id == user
             end) do
      raise ArgumentError, "normal import rows need uniform columns and matching user/import"
    end

    unless repo.query!("SELECT user_id FROM imports WHERE id = $1", [id], log: false).rows ==
             [[user]] do
      raise ArgumentError, "normal import context does not match database owner"
    end
  end

  defp stamp(rows, cache, repo, fence) do
    if SourceDimensions.available?(repo) do
      {stamped, cache} =
        Enum.map_reduce(rows, cache, fn row, cache ->
          combo = SourceDimensions.combo(row)

          id =
            Map.get_lazy(cache, combo, fn ->
              fence.(fn -> SourceDimensions.resolve(repo, combo) end)
            end)

          cache = if id, do: remember(cache, combo, id), else: cache
          {Map.put(row, :source_id, id), cache}
        end)

      {Enum.map(stamped, &cast/1), cache}
    else
      {Enum.map(rows, &cast/1), cache}
    end
  end

  defp remember(cache, combo, id) do
    if Map.has_key?(cache, combo) or map_size(cache) < @limit,
      do: Map.put(cache, combo, id),
      else: %{combo => id}
  end

  defp cast(row) do
    Map.new(row, fn
      {:lonlat, value} -> {:lonlat, Geometry.serialize(value)}
      {key, value} when key in [:source_id, :import_id, :created_at, :updated_at] -> {key, value}
      {key, value} -> {key, NormalCast.column(key, value)}
    end)
  end

  defp insert!(rows, repo) do
    columns = rows |> hd() |> Map.keys() |> Enum.sort()
    width = length(columns)

    placeholders =
      Enum.map_join(Enum.with_index(rows), ", ", fn {_row, i} ->
        "(" <>
          Enum.map_join(Enum.with_index(columns), ", ", fn {column, j} ->
            "$#{i * width + j + 1}#{suffix(column)}"
          end) <> ")"
      end)

    sql =
      "INSERT INTO points (#{Enum.map_join(columns, ", ", &~s("#{&1}"))}) VALUES " <>
        placeholders <>
        " ON CONFLICT (user_id, timestamp, lonlat) DO NOTHING RETURNING id"

    repo.query!(sql, Enum.flat_map(rows, &Enum.map(columns, fn column -> &1[column] end)),
      log: false
    ).num_rows
  end

  defp suffix(:lonlat), do: "::text::geography"
  defp suffix(column) when column in [:motion_data, :raw_data], do: "::text::jsonb"
  defp suffix(column) when column in [:inrids, :in_regions], do: "::text::text[]"
  defp suffix(_), do: ""

  defp counters!(attempted, skipped, import, repo) do
    repo.query!(
      "UPDATE imports SET raw_points = COALESCE(raw_points, 0) + $2, doubles = CASE WHEN $3 > 0 THEN COALESCE(doubles, 0) + $3 ELSE doubles END WHERE id = $1",
      [import.id, attempted, skipped],
      log: false
    )
  end
end
