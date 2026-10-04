defmodule Dawarich.Digests.LocationTime do
  @moduledoc false

  alias Dawarich.Digests.Toponyms

  def calculate(repo, context, period, stats) do
    zone = if period.month, do: period.zone, else: "Etc/UTC"
    order = if period.month, do: "min_timestamp", else: "point_date, min_timestamp"

    days =
      repo.query!(
        "SELECT (to_timestamp(timestamp) AT TIME ZONE $4)::date AS point_date, " <>
          "country_name, min(timestamp) AS min_timestamp, max(timestamp) AS max_timestamp " <>
          "FROM public.points WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 " <>
          "AND country_name IS NOT NULL AND country_name <> '' " <>
          "GROUP BY point_date, country_name ORDER BY #{order}",
        [context.user_id, period.location_first, period.last, zone],
        log: false
      ).rows
      |> Enum.reduce([], fn [day, name, first, last], days ->
        Toponyms.add(days, day, [{name, max(last - first, 60)}], &(&1 ++ &2))
      end)

    minutes =
      Enum.reduce(days, [], fn {_, spans}, minutes ->
        Enum.reduce(allocate(spans), minutes, fn {name, value}, acc ->
          Toponyms.add(acc, name, value)
        end)
      end)

    %{
      "countries" => Toponyms.ranked(minutes),
      "cities" => Toponyms.city_minutes(stats),
      "total_country_minutes" => Enum.sum(Enum.map(minutes, &elem(&1, 1)))
    }
  end

  defp allocate(spans) do
    total = Enum.sum(Enum.map(spans, &elem(&1, 1)))
    Enum.map(spans, fn {name, span} -> {name, round(span / total * 1440)} end)
  end
end
