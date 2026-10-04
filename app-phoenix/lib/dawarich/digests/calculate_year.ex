defmodule Dawarich.Digests.CalculateYear do
  @moduledoc false

  alias Dawarich.Digests.{
    Activity,
    Comparison,
    LocationTime,
    Period,
    Queries,
    Seasonality,
    TimeOfDay,
    Toponyms
  }

  alias Dawarich.RubyInteger

  def attributes(repo, context, year) do
    year = RubyInteger.to_i(year)
    stats = Queries.yearly(repo, context, year)

    if stats != [] do
      period = Period.yearly(repo, context, year)
      history = Queries.history(repo, context)
      distances = Map.new(stats, &{to_string(&1["month"]), to_string(&1["distance"])})

      %{
        "distance" => Enum.sum(Enum.map(stats, & &1["distance"])),
        "toponyms" => Toponyms.aggregate(stats),
        "monthly_distances" => Map.merge(Map.new(1..12, &{to_string(&1), "0"}), distances),
        "time_spent_by_location" => LocationTime.calculate(repo, context, period, stats),
        "first_time_visits" => Toponyms.first_visits(history, year),
        "year_over_year" => Comparison.yearly(history, year),
        "all_time_stats" => Comparison.all_time(history, Queries.distance(repo, context)),
        "travel_patterns" => %{
          "time_of_day" => TimeOfDay.calculate(repo, context, period),
          "activity_breakdown" => Activity.calculate(repo, context, period),
          "seasonality" => Seasonality.calculate(repo, context, year)
        }
      }
    end
  end
end
