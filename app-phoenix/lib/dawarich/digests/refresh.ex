defmodule Dawarich.DigestRefresh do
  @moduledoc "Synchronous source-compatible CalculateYear/CalculateMonth persistence."
  alias Dawarich.Digests
  alias Dawarich.Digests.Refresh.{Activity, Aggregate, Context, Patterns, TimeSpent, Writer}

  def year(user_id, raw_year, opts \\ []) do
    year = Digests.to_i(raw_year)
    context = Context.load(user_id, opts)
    stats = Context.stats(context)
    scoped = Context.scoped(stats, context.cutoff)
    selected = scoped |> Enum.filter(&(&1["year"] == year)) |> Enum.sort_by(& &1["month"])

    if selected != [] do
      {first, last, starts, ends} = Context.bounds(context, year, nil)
      lower = if context.point_cutoff, do: max(first, context.point_cutoff), else: first
      countries = TimeSpent.fetch(context.repo, user_id, lower, last, "UTC")
      activity = Activity.fetch_pairs(context, starts, ends)

      attrs =
        Aggregate.year(selected)
        |> Map.merge(%{
          "time_spent_by_location" => TimeSpent.compose(countries, selected),
          "first_time_visits" => Aggregate.first(stats, year, nil),
          "year_over_year" => Aggregate.comparison(stats, year, nil),
          "all_time_stats" => Aggregate.all_time(stats, scoped),
          "travel_patterns" => %{
            "time_of_day" =>
              Patterns.time_of_day(context.repo, user_id, first, last, context.query_zone),
            "seasonality" => Patterns.seasons(selected, context.southern),
            "activity_breakdown" => Map.new(activity)
          }
        })

      attrs = Dawarich.RailsCache.JsonOrder.fresh(attrs, activity)
      Writer.save(context, year, nil, attrs)
    end
  end

  def month(user_id, raw_year, raw_month, opts \\ []) do
    {year, month} = {Digests.to_i(raw_year), Digests.to_i(raw_month)}
    context = Context.load(user_id, opts)
    stats = Context.stats(context)
    stat = Enum.find(stats, &(&1["year"] == year and &1["month"] == month))

    if stat do
      {first, last, starts, ends} = Context.bounds(context, year, month)
      countries = TimeSpent.fetch(context.repo, user_id, first, last, context.zone)
      activity = Activity.fetch_pairs(context, starts, ends)

      attrs =
        Aggregate.month(stat)
        |> Map.merge(%{
          "time_spent_by_location" => TimeSpent.compose(countries, [stat]),
          "first_time_visits" => Aggregate.first(stats, year, month),
          "year_over_year" => Aggregate.comparison(stats, year, month),
          "all_time_stats" => Aggregate.all_time(stats, Context.scoped(stats, context.cutoff)),
          "travel_patterns" => %{
            "time_of_day" =>
              Patterns.time_of_day(context.repo, user_id, first, last, context.query_zone),
            "activity_breakdown" => Map.new(activity)
          }
        })

      attrs = Dawarich.RailsCache.JsonOrder.fresh(attrs, activity)
      Writer.save(context, year, month, attrs)
    end
  end
end
