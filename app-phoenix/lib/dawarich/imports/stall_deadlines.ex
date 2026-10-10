defmodule Dawarich.Imports.StallDeadlines do
  @moduledoc false

  def nearest(records, now) do
    records
    |> Enum.flat_map(&deadlines/1)
    |> Enum.filter(&(DateTime.compare(&1, now) == :gt))
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp deadlines(record) do
    deletion =
      if record.status in [4, "deleting"],
        do: deadline(Map.get(record, :updated_at), 3600),
        else: []

    extraction =
      if Map.get(record, :additional_data_extraction_status) in [1, 2] and
           Map.get(record, :source) in [0, 3, 4, 13] do
        data = Map.get(record, :additional_data_extraction) || %{}
        deadline(data["started_at"], 21600)
      else
        []
      end

    deletion ++ extraction
  end

  defp deadline(%NaiveDateTime{} = at, seconds),
    do: [at |> DateTime.from_naive!("Etc/UTC") |> DateTime.add(seconds)]

  defp deadline(%DateTime{} = at, seconds), do: [DateTime.add(at, seconds)]

  defp deadline(at, seconds) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, parsed, _} -> deadline(parsed, seconds)
      _ -> []
    end
  end

  defp deadline(_, _), do: []
end
