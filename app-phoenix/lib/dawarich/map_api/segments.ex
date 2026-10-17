defmodule Dawarich.MapApi.Segments do
  @moduledoc false

  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)
  @emojis ~w(❓ 📍 🚶 🏃 🚴 🚗 🚌 🚆 ✈️ ⛵ 🏍️)
  @colors ~w(#CBD5E1 #94A3B8 #22C55E #F97316 #3B82F6 #EF4444 #EAB308 #84CC16 #06B6D4 #14B8A6 #EC4899)

  def mode(number) when number in 0..10, do: Enum.at(@modes, number)
  def mode(_number), do: nil
  def emoji(number) when number in 0..10, do: Enum.at(@emojis, number)
  def emoji(_number), do: "❓"

  def timeline([], _track), do: []

  def timeline(rows, track) do
    rows = sorted(rows)

    if Enum.all?(rows, & &1["start_at"]),
      do: Enum.map(rows, &moment(&1, trunc(epoch(&1["start_at"])), trunc(epoch(&1["end_at"])))),
      else: legacy(rows, track)
  end

  def full(rows, track) do
    rows
    |> sorted()
    |> Enum.map_reduce(epoch(track["start_at"]), fn row, current ->
      next = current + (row["duration"] || 0)

      {from, to} =
        if row["start_at"] && row["end_at"],
          do: {epoch(row["start_at"]), epoch(row["end_at"])},
          else: {current, next}

      {{:object,
        [
          {"id", row["id"]},
          {"mode", mode(row["transportation_mode"])},
          {"emoji", emoji(row["transportation_mode"])},
          {"color", color(row["transportation_mode"])},
          {"start_index", row["start_index"]},
          {"end_index", row["end_index"]},
          {"coordinates", row["coordinates"]},
          {"distance", row["distance"]},
          {"duration", row["duration"]},
          {"avg_speed", row["avg_speed"]},
          {"confidence", confidence(row["confidence"])},
          {"start_time", trunc(from)},
          {"end_time", trunc(to)}
        ]}, next}
    end)
    |> elem(0)
  end

  def epoch(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond) / 1_000_000
  def epoch(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> epoch()

  defp legacy(rows, track) do
    first = epoch(track["start_at"])
    span = epoch(track["end_at"]) - first
    count = (List.last(rows)["end_index"] || 0) + 1

    Enum.map(rows, fn row ->
      moment(
        row,
        trunc(first + (row["start_index"] || 0) / count * span),
        trunc(first + (row["end_index"] + 1) / count * span)
      )
    end)
  end

  defp moment(row, from, to),
    do:
      {:object,
       [{"start_time", from}, {"end_time", to}, {"emoji", emoji(row["transportation_mode"])}]}

  defp sorted(rows),
    do:
      Enum.sort_by(rows, fn row ->
        if row["start_at"], do: epoch(row["start_at"]), else: (row["start_index"] || 0) * 1.0
      end)

  def color(number) when number in 0..10, do: Enum.at(@colors, number)
  def color(_number), do: "#CBD5E1"

  defp confidence(number) when number in 0..2, do: Enum.at(~w(low medium high), number)
  defp confidence(_number), do: nil
end
