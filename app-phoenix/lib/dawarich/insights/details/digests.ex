defmodule Dawarich.Insights.Details.Digests do
  @moduledoc false
  alias Dawarich.{DigestRefresh, Digests, RailsCache}
  alias Dawarich.RailsCache.Snapshot
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def yearly(context, year, stats, opts) do
    case find(context, year, nil) do
      nil ->
        if(!opts[:read_only], do: refresh(context.id, year, nil, opts))

      digest ->
        key = key(context.id, year, digest["updated_at"])
        cache = opts[:cache] || []

        case RailsCache.get(key, cache) do
          {:ok, nil} ->
            nil

          {:ok, value} ->
            Snapshot.decode(value)

          _ ->
            if opts[:read_only] do
              digest
            else
              selected = Enum.filter(stats, &(&1["year"] == year))

              value =
                if Ruby.blank?(digest["travel_patterns"]) or stale?(digest, selected),
                  do: refresh(context.id, year, nil, opts),
                  else: digest

              RailsCache.put(
                key,
                if(value, do: Snapshot.encode(value)),
                cache ++ [expires_in: 3600]
              )

              value
            end
        end
    end
  end

  def monthly(context, year, month, available, stats, opts) do
    digest = find(context, year, month)
    selected = Enum.filter(stats, &(&1["year"] == year and &1["month"] == month))

    if opts[:read_only] != true and month in available and
         (digest == nil or stale?(digest, selected)),
       do: refresh(context.id, year, month, opts),
       else: digest
  end

  def key(user, year, updated) do
    epoch = updated |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    "insights/yearly_digest/#{user}/#{year}/#{epoch}"
  end

  def weekly(context, year) do
    result =
      context.repo.query!(
        "SELECT year,month,monthly_distances FROM digests WHERE user_id=$1 AND year=$2 AND period_type=0",
        [context.id, year]
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

  defp find(context, year, month) do
    period = if month == nil, do: 1, else: 0

    case context.repo.query!(
           "SELECT *,travel_patterns::text AS _rails_patterns FROM digests WHERE user_id=$1 AND year=$2 AND period_type=$3 AND ($4::integer IS NULL OR month=$4) LIMIT 1",
           [context.id, year, period, month]
         ) do
      %{rows: []} -> nil
      %{rows: [row], columns: columns} -> Map.new(Enum.zip(columns, row)) |> normalize()
    end
  end

  defp refresh(id, year, month, opts) do
    value =
      if month == nil,
        do: DigestRefresh.year(id, year, opts),
        else: DigestRefresh.month(id, year, month, opts)

    if value, do: normalize(value)
  end

  defp normalize(value) do
    {raw, value} = Map.pop(value, "_rails_patterns")
    value = if raw, do: Map.put(value, "_rails_json", %{"travel_patterns" => raw}), else: value
    value |> Snapshot.encode() |> Snapshot.decode()
  end

  defp stale?(_digest, []), do: false

  defp stale?(digest, stats),
    do:
      NaiveDateTime.compare(
        digest["updated_at"],
        Enum.max_by(stats, & &1["updated_at"], NaiveDateTime)["updated_at"]
      ) == :lt
end
