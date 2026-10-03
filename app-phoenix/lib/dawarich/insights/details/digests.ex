defmodule Dawarich.Insights.Details.Digests do
  @moduledoc false
  alias Dawarich.{Digests, RailsCache, Repo}
  alias Dawarich.RailsCache.Snapshot

  def yearly(id, year, stats) do
    case find(id, year, nil) do
      nil ->
        {nil, Enum.any?(stats, &(&1["year"] == year))}

      digest ->
        case RailsCache.get(key(id, year, digest["updated_at"])) do
          {:ok, nil} -> {nil, false}
          {:ok, value} -> {Snapshot.decode(value), false}
          _ -> {digest, true}
        end
    end
  end

  def monthly(id, year, month, available, stats) do
    digest = find(id, year, month)
    selected = Enum.filter(stats, &(&1["year"] == year and &1["month"] == month))
    {digest, month in available and (digest == nil or stale?(digest, selected))}
  end

  def key(user, year, updated) do
    epoch = updated |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    "insights/yearly_digest/#{user}/#{year}/#{epoch}"
  end

  def weekly(id, year) do
    result =
      Repo.query!(
        "SELECT year,month,monthly_distances FROM digests WHERE user_id=$1 AND year=$2 AND period_type=0",
        [id, year]
      )

    Enum.reduce(result.rows, List.duplicate(0, 7), fn [year, month, daily], totals ->
      Enum.zip_with(totals, weekly_pattern(year, month, daily), &(&1 + &2))
    end)
  end

  def weekly_pattern(_year, nil, _daily), do: List.duplicate(0, 7)

  def weekly_pattern(year, month, daily) do
    pairs =
      case daily do
        %{} ->
          Enum.sort_by(daily, fn {day, _} -> Digests.to_i(day) end)

        list when is_list(list) ->
          Enum.map(list, fn [day, n] -> {day, n} end) |> Enum.sort_by(fn {day, _} -> day end)

        _ ->
          []
      end

    Enum.reduce(pairs, List.duplicate(0, 7), fn {day, n}, acc ->
      if month not in 1..12, do: raise(ArgumentError, "mon out of range")

      date =
        case Date.new(year, month, Digests.to_i(day)) do
          {:ok, date} -> date
          {:error, _} -> raise(ArgumentError, "invalid date")
        end

      List.update_at(acc, Date.day_of_week(date) - 1, &(&1 + Digests.to_i(n)))
    end)
  end

  defp find(id, year, month) do
    period = if month == nil, do: 1, else: 0

    case Repo.query!(
           "SELECT *,travel_patterns::text AS _rails_patterns FROM digests WHERE user_id=$1 AND year=$2 AND period_type=$3 AND ($4::integer IS NULL OR month=$4) LIMIT 1",
           [id, year, period, month]
         ) do
      %{rows: []} ->
        nil

      %{rows: [row], columns: columns} ->
        {raw, digest} = columns |> Enum.zip(row) |> Map.new() |> Map.pop("_rails_patterns")
        Map.put(digest, "_rails_json", %{"travel_patterns" => raw})
    end
  end

  defp stale?(_digest, []), do: false

  defp stale?(digest, stats),
    do:
      NaiveDateTime.compare(
        digest["updated_at"],
        Enum.max_by(stats, & &1["updated_at"], NaiveDateTime)["updated_at"]
      ) == :lt
end
