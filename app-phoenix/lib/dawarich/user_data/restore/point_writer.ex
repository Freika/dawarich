defmodule Dawarich.UserData.Restore.PointWriter do
  @moduledoc false
  alias Dawarich.UserData.Restore.Batch
  alias Dawarich.Imports.{Fence, SourceDimensions, NormalCast}
  @combo ~w(tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)a
  @integers ~w(accuracy altitude battery vertical_accuracy timestamp mode lock_version)

  def write(repo, rows, cache, context) when length(rows) <= 5000 do
    keys = rows |> Enum.flat_map(&Map.keys/1) |> Enum.uniq() |> Enum.sort()
    rows = Enum.map(rows, fn row -> Map.new(keys, &{&1, row[&1]}) end)
    {rows, cache} = stamp(repo, rows, cache, context)
    count = insert(repo, rows, context)
    {count, cache}
  end

  defp stamp(repo, rows, cache, context) do
    Fence.run(context, fn ->
      if SourceDimensions.available?(repo) do
        Enum.map_reduce(rows, cache, fn row, cache ->
          atoms =
            Map.new(
              for key <- @combo,
                  Map.has_key?(row, Atom.to_string(key)),
                  do: {key, row[Atom.to_string(key)]}
            )

          combo = SourceDimensions.combo(atoms)
          id = Map.get_lazy(cache, combo, fn -> SourceDimensions.resolve(repo, combo) end)

          cache =
            if id,
              do: Map.put(if(map_size(cache) >= 5000, do: %{}, else: cache), combo, id),
              else: cache

          {Map.put(row, "source_id", id), cache}
        end)
      else
        {rows, cache}
      end
    end)
  end

  defp insert(repo, rows, context) do
    cast =
      Enum.map(rows, fn row ->
        row =
          Map.new(row, fn {key, value} ->
            {key, if(key in @integers, do: NormalCast.integer(value), else: value)}
          end)

        row
      end)
      |> then(&Batch.rows!(repo, "points", &1, context))

    keys = hd(cast) |> Map.keys() |> Enum.sort()
    names = Enum.map_join(keys, ",", &~s("#{&1}"))
    select = Enum.map_join(keys, ",", &~s(r."#{&1}"))

    Fence.run(context, fn ->
      case repo.query(
             "INSERT INTO points(#{names}) SELECT #{select} FROM jsonb_populate_recordset(NULL::points,$1::jsonb) r ON CONFLICT(user_id,timestamp,lonlat) DO NOTHING RETURNING id",
             [cast],
             log: false
           ) do
        {:ok, %{num_rows: count}} ->
          if count > 0 do
            Dawarich.RailsEffects.tile_epoch(
              repo,
              hd(cast)["user_id"],
              Enum.map(cast, & &1["timestamp"])
            )
          end

          count

        {:error, _} ->
          0
      end
    end)
  rescue
    e in Dawarich.Imports.LeaseLost -> reraise e, __STACKTRACE__
    _ -> 0
  end
end
