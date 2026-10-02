defmodule Dawarich.Insights.Details do
  @moduledoc "Source details GET data, synchronous refresh ordering and shared Rails cache contract."
  alias Dawarich.LocalTime
  alias Dawarich.Digests.Refresh.Context
  alias Dawarich.Insights.Details.Digests, as: DetailDigests
  alias DawarichWeb.StatsFormat

  def load(user, params, opts \\ []) do
    now = opts[:now] || DateTime.utc_now()
    context = Context.load(user.id, opts)
    stats = Context.stats(context)
    scoped = Context.scoped(stats, context.cutoff)
    valid = Enum.filter(stats, &(&1["month"] in 1..12))
    scoped_valid = Enum.filter(scoped, &(&1["month"] in 1..12))
    available = valid |> Enum.map(& &1["year"]) |> Enum.uniq() |> Enum.sort(:desc)
    restricted = context.cutoff != nil
    locked = if restricted, do: available -- Enum.map(scoped_valid, & &1["year"]), else: []
    {_zone, today} = LocalTime.local(user.settings, now)
    raw = params["year"] || to_string(List.first(available) || today.year)
    year = if raw == "all", do: nil, else: Dawarich.Digests.to_i(raw)

    data = %{
      available: available,
      locked: locked,
      restricted: restricted,
      year_locked: year in locked,
      all_time: raw == "all",
      year: year,
      selected: year || "all",
      unit: StatsFormat.unit(user.settings),
      today: today
    }

    year_stats =
      if data.all_time,
        do: Enum.sort_by(scoped_valid, &{&1["year"], &1["month"]}, :desc),
        else: Enum.filter(scoped_valid, &(&1["year"] == year)) |> Enum.sort_by(& &1["month"])

    data =
      Map.merge(data, %{stats: year_stats, max_stat_updated: maximum(year_stats, "updated_at")})

    if data.year_locked or restricted do
      data
    else
      totals = Dawarich.Insights.Details.Totals.calculate(year_stats, data.unit)
      previous = if year, do: Enum.filter(scoped_valid, &(&1["year"] == year - 1)), else: []

      comparison =
        if previous != [],
          do: Dawarich.Insights.Details.Totals.comparison(totals, previous, data.unit)

      data = Map.merge(data, %{totals: totals, comparison: comparison})

      if data.all_time,
        do: Map.merge(data, defaults()),
        else: patterns(data, context, scoped, params, opts)
    end
  end

  defdelegate yearly_key(id, year, updated), to: DetailDigests, as: :key

  defp patterns(data, context, stats, params, opts) do
    yearly = DetailDigests.yearly(context, data.year, stats, opts)
    patterns = if yearly, do: yearly["travel_patterns"] || %{}, else: %{}
    weekly = DetailDigests.weekly(context, data.year)
    visits = top_visits(context, data.year)
    months = for s <- stats, s["year"] == data.year, do: s["month"]

    month =
      if params["month"] not in [nil, "", false],
        do: Dawarich.Digests.to_i(params["month"]),
        else:
          Enum.max(months, fn ->
            if data.year == data.today.year, do: data.today.month, else: 12
          end)

    monthly = DetailDigests.monthly(context, data.year, month, months, stats, opts)
    orders = if yearly, do: Dawarich.RailsCache.JsonOrder.pattern_pairs(yearly), else: %{}
    data = Map.merge(data, orders)

    Map.merge(data, %{
      yearly: yearly,
      monthly: monthly,
      selected_month: month,
      available_months: Enum.sort(months),
      weekly: weekly,
      time_of_day: patterns["time_of_day"] || %{},
      seasonality: patterns["seasonality"] || %{},
      activity: patterns["activity_breakdown"] || %{},
      top_visits: visits
    })
  end

  defp top_visits(context, year) do
    {_first, _last, first, last} = Context.bounds(context, year, nil)

    for [name, count, duration] <-
          context.repo.query!(
            "SELECT name,COUNT(*),SUM(duration) FROM visits WHERE user_id=$1 AND status=1 AND deleted_at IS NULL AND started_at BETWEEN $2 AND $3 GROUP BY name ORDER BY COUNT(*) DESC,SUM(duration) DESC LIMIT 5",
            [context.id, first, last]
          ).rows,
        do: %{name: name, visit_count: count, total_duration: duration}
  end

  defp maximum([], _key), do: nil
  defp maximum(rows, key), do: Enum.max_by(rows, & &1[key], NaiveDateTime)[key]

  defp defaults,
    do: %{
      yearly: nil,
      monthly: nil,
      selected_month: "all",
      available_months: [],
      weekly: List.duplicate(0, 7),
      time_of_day: %{},
      seasonality: %{},
      activity: %{},
      top_visits: []
    }
end
