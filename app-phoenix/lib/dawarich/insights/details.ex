defmodule Dawarich.Insights.Details do
  @moduledoc "Reads for Rails' InsightsController#details; `rails` marks a request whose digest Rails would refresh or cache."
  alias Dawarich.{Repo, Stats}
  alias Dawarich.Insights.Details.Digests, as: DetailDigests
  alias Dawarich.Insights.Details.Totals
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.StatsFormat

  def load(user, params, opts \\ []) do
    if opts[:fill] == true and
         Enum.any?([params["year"], params["month"]], &(is_map(&1) or is_list(&1))),
       do: raise(ArgumentError, "invalid insights period")

    now = opts[:now] || DateTime.utc_now()
    self_hosted = Keyword.get_lazy(opts, :self_hosted, &DawarichWeb.LayoutAssigns.self_hosted?/0)
    context = Stats.context(user, now, self_hosted)
    result = Repo.query!("SELECT * FROM stats WHERE user_id=$1", [user.id])
    stats = for row <- result.rows, do: Map.new(Enum.zip(result.columns, row))

    scoped =
      Enum.filter(
        stats,
        &Stats.in_window?(%{year: &1["year"], month: &1["month"]}, context.cutoff)
      )

    valid = Enum.filter(stats, &(&1["month"] in 1..12))
    scoped_valid = Enum.filter(scoped, &(&1["month"] in 1..12))
    available = valid |> Enum.map(& &1["year"]) |> Enum.uniq() |> Enum.sort(:desc)

    locked =
      if context.restricted, do: available -- Enum.map(scoped_valid, & &1["year"]), else: []

    raw = params["year"] || to_string(List.first(available) || context.today.year)
    year = if raw == "all", do: nil, else: Dawarich.Digests.to_i(raw)

    data = %{
      rails: false,
      available: available,
      locked: locked,
      restricted: context.restricted,
      year_locked: year in locked,
      all_time: raw == "all",
      year: year,
      selected: year || "all",
      unit: StatsFormat.unit(Dawarich.UserSettings.get(user)),
      today: context.today
    }

    year_stats =
      if data.all_time,
        do: Enum.sort_by(scoped_valid, &{&1["year"], &1["month"]}, :desc),
        else: Enum.filter(scoped_valid, &(&1["year"] == year)) |> Enum.sort_by(& &1["month"])

    data =
      Map.merge(data, %{stats: year_stats, max_stat_updated: maximum(year_stats, "updated_at")})

    if data.year_locked or data.restricted do
      data
    else
      totals = Totals.calculate(year_stats, data.unit)
      previous = if year, do: Enum.filter(scoped_valid, &(&1["year"] == year - 1)), else: []
      comparison = if previous != [], do: Totals.comparison(totals, previous, data.unit)
      data = Map.merge(data, %{totals: totals, comparison: comparison})

      if data.all_time,
        do: Map.merge(data, defaults()),
        else: patterns(data, user.id, context.zone, scoped, params, opts)
    end
  end

  defdelegate yearly_key(id, year, updated), to: DetailDigests, as: :key

  defp patterns(data, id, zone, stats, params, opts) do
    calculation = [now: opts[:now] || DateTime.utc_now(), ambient_zone: zone]

    {yearly, yearly_rails} =
      if opts[:fill],
        do: DetailDigests.native_yearly(id, data.year, stats, calculation),
        else: DetailDigests.yearly(id, data.year, stats)

    patterns = if yearly, do: yearly["travel_patterns"] || %{}, else: %{}
    months = for s <- stats, s["year"] == data.year, do: s["month"]

    month =
      if Ruby.present?(params["month"]),
        do: Dawarich.Digests.to_i(params["month"]),
        else:
          Enum.max(months, fn ->
            if data.year == data.today.year, do: data.today.month, else: 12
          end)

    {monthly, monthly_rails} =
      if opts[:fill],
        do: DetailDigests.native_monthly(id, data.year, month, months, stats, calculation),
        else: DetailDigests.monthly(id, data.year, month, months, stats)

    orders = if yearly, do: Dawarich.RailsCache.JsonOrder.pattern_pairs(yearly), else: %{}

    data
    |> Map.merge(orders)
    |> Map.merge(%{
      rails: yearly_rails or monthly_rails,
      yearly: yearly,
      monthly: monthly,
      selected_month: month,
      available_months: Enum.sort(months),
      weekly: DetailDigests.weekly(id, data.year),
      time_of_day: patterns["time_of_day"] || %{},
      seasonality: patterns["seasonality"] || %{},
      activity: patterns["activity_breakdown"] || %{},
      top_visits: top_visits(id, zone, data.year)
    })
  end

  defp top_visits(id, zone, year) do
    for [name, count, duration] <-
          Repo.query!(
            """
            SELECT name,COUNT(*),SUM(duration) FROM visits
            WHERE user_id=$1 AND status=1 AND deleted_at IS NULL
              AND started_at BETWEEN make_timestamptz($2,1,1,0,0,0,$3)
                AND (make_date($2,12,1)::timestamp + interval '1 month' - interval '1 microsecond') AT TIME ZONE $3
            GROUP BY name ORDER BY COUNT(*) DESC,SUM(duration) DESC,name COLLATE "C" LIMIT 5
            """,
            [id, if(year <= 0, do: year - 1, else: year), zone]
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
