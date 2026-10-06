defmodule Dawarich.Insights do
  @moduledoc false

  alias Dawarich.{Repo, Stats}
  alias Dawarich.Insights.Heatmap
  alias Dawarich.Stats.Toponyms
  alias DawarichWeb.{Params, StatsFormat}

  def page(user, params, context) do
    if is_list(params["year"]) or is_map(params["year"]),
      do: raise(ArgumentError, "year does not support to_i")

    rows = rows(user.id)
    available = rows |> Enum.map(& &1.year) |> Enum.uniq() |> Enum.sort(:desc)
    scoped = Enum.filter(rows, &Stats.in_window?(&1, context.cutoff))
    scoped_years = MapSet.new(scoped, & &1.year)

    locked =
      if context.restricted,
        do: Enum.reject(available, &MapSet.member?(scoped_years, &1)),
        else: []

    selected = selected(params["year"], available, context.today)
    all_time = selected == "all"
    year = if all_time, do: nil, else: year!(selected)
    year_locked = year in locked

    page = %{
      available: available,
      locked: locked,
      all_time: all_time,
      year: year,
      selected: if(all_time, do: "all", else: Integer.to_string(year)),
      year_locked: year_locked,
      restricted: context.restricted
    }

    if year_locked do
      page
    else
      stats = if all_time, do: scoped, else: Enum.filter(scoped, &(&1.year == year))
      Enum.each(stats, &validate_daily!(&1.daily_distance))

      Map.merge(page, %{
        selected_month: selected_month(params["month"], stats, year, context.today),
        totals: totals(stats, StatsFormat.unit(user.settings)),
        heatmap: if(all_time, do: nil, else: Heatmap.build(stats, year, context.today))
      })
    end
  end

  defp selected_month(raw, stats, year, today) do
    if is_binary(raw) and raw != "",
      do: Dawarich.Digests.to_i(raw),
      else:
        stats
        |> Enum.map(& &1.month)
        |> Enum.max(fn -> if year == today.year, do: today.month, else: 12 end)
  end

  defp validate_daily!(daily) when is_map(daily), do: :ok

  defp validate_daily!(daily) when is_list(daily) do
    unless Enum.all?(daily, &match?([_, _], &1)),
      do: raise(ArgumentError, "invalid daily_distance pairs")
  end

  defp validate_daily!(_daily), do: raise(ArgumentError, "invalid daily_distance")

  defp selected(year, _available, _today) when is_binary(year), do: year
  defp selected(_year, [newest | _], _today), do: Integer.to_string(newest)
  defp selected(_year, [], today), do: Integer.to_string(today.year)

  defp year!(selected) do
    year = Params.ruby_to_i(selected)
    if abs(year) > 9999, do: raise(DawarichWeb.NotFoundError), else: year
  end

  defp totals(stats, unit) do
    toponyms = Enum.flat_map(stats, & &1.toponyms)

    %{
      distance: StatsFormat.rounded(stats |> Enum.map(& &1.distance) |> Enum.sum(), unit),
      countries: length(Toponyms.countries(toponyms)),
      cities: length(Toponyms.cities(toponyms)),
      days: stats |> Enum.map(&Heatmap.active_days(&1.daily_distance)) |> Enum.sum(),
      any: stats != []
    }
  end

  defp rows(user_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT year, month, distance, toponyms, daily_distance FROM stats WHERE user_id = $1 AND month BETWEEN 1 AND 12",
        [user_id]
      )

    for [year, month, distance, toponyms, daily] <- rows do
      %{
        year: year,
        month: month,
        distance: distance,
        toponyms: Toponyms.sanitize(toponyms),
        daily_distance: daily
      }
    end
  end
end
