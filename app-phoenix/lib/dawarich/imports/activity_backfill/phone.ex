defmodule Dawarich.Imports.ActivityBackfill.Phone do
  @moduledoc false
  alias Dawarich.Imports.ActivityBackfill.Semantic
  alias Dawarich.Imports.JsonStream
  alias Dawarich.Imports.JsonStream.Section

  def run(repo, import_id, path, context) do
    section =
      case Section.last(path, "rawSignals") do
        {%{kind: :object}, %{kind: :array} = section} -> section
        {%{kind: :array} = root, _} -> root
        _ -> nil
      end

    points =
      repo.query!(
        "SELECT id,timestamp FROM points WHERE import_id=$1 ORDER BY timestamp,id",
        [import_id],
        log: false
      ).rows
      |> List.to_tuple()

    if section && tuple_size(points) > 0 do
      chosen =
        Section.reduce(path, section, %{}, fn signal, chosen ->
          choose(Semantic.plain(signal), points, context, chosen)
        end)

      for {id, {record, _distance}} <- chosen do
        repo.query!(
          "UPDATE points SET motion_data=COALESCE(motion_data,'{}'::jsonb) || $2::jsonb WHERE id=$1",
          [id, %{"activityRecord" => record}],
          log: false
        )
      end
    end

    :ok
  rescue
    error in JsonStream.Error ->
      if error.reason == :syntax, do: :ok, else: reraise(error, __STACKTRACE__)
  end

  defp choose(%{"activityRecord" => record}, points, context, chosen) when is_map(record) do
    with timestamp when not is_nil(timestamp) <- Semantic.timestamp(record["timestamp"], context),
         {id, distance} <- nearest(points, timestamp) do
      case chosen[id] do
        {_, previous} when previous <= distance -> chosen
        _ -> Map.put(chosen, id, {record, distance})
      end
    else
      _ -> chosen
    end
  end

  defp choose(_signal, _points, _context, chosen), do: chosen

  defp nearest(points, timestamp) do
    index = upper_bound(points, timestamp, 0, tuple_size(points))

    candidates =
      [
        if(index > 0, do: elem(points, index - 1)),
        if(index < tuple_size(points), do: elem(points, index))
      ]
      |> Enum.reject(&is_nil/1)

    [id, stamp] = Enum.min_by(candidates, fn [_, stamp] -> abs(stamp - timestamp) end)
    distance = abs(stamp - timestamp)
    if distance <= 60, do: {id, distance}
  end

  defp upper_bound(_points, _timestamp, low, high) when low == high, do: low

  defp upper_bound(points, timestamp, low, high) do
    middle = div(low + high, 2)
    [_, stamp] = elem(points, middle)

    if stamp > timestamp,
      do: upper_bound(points, timestamp, low, middle),
      else: upper_bound(points, timestamp, middle + 1, high)
  end
end
