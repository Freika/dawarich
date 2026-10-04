defmodule Dawarich.Digests.CalculateMonth do
  @moduledoc false

  alias Dawarich.Digests.{
    Activity,
    Comparison,
    LocationTime,
    Period,
    Queries,
    TimeOfDay,
    Toponyms
  }

  alias Dawarich.RubyInteger

  defmodule InvalidDaily do
    defexception [:message]
  end

  def attributes(repo, context, year, month) do
    year = RubyInteger.to_i(year)
    month = RubyInteger.to_i(month)
    stat = Queries.monthly(repo, context, year, month)

    if stat do
      period = Period.monthly(repo, context, year, month)
      history = Queries.history(repo, context)

      %{
        "distance" => stat["distance"],
        "flight_distance" => stat["flight_distance"],
        "toponyms" => Toponyms.sanitize(stat["toponyms"]),
        "monthly_distances" => daily(stat["daily_distance"]),
        "time_spent_by_location" => LocationTime.calculate(repo, context, period, [stat]),
        "first_time_visits" => Toponyms.first_visits(history, year, month),
        "year_over_year" => Comparison.monthly(history, year, month),
        "all_time_stats" => Comparison.all_time(history, Queries.distance(repo, period.context)),
        "travel_patterns" => %{
          "time_of_day" => TimeOfDay.calculate(repo, context, period),
          "activity_breakdown" => Activity.calculate(repo, context, period)
        }
      }
    end
  end

  defp daily(nil), do: %{}
  defp daily(value) when is_map(value), do: value

  defp daily(value) when is_list(value),
    do: Map.new(value, fn [key, value] -> {to_string(key), value} end)

  defp daily(value) do
    type =
      if is_binary(value),
        do: "String",
        else: if(is_number(value), do: "Integer", else: "TrueClass")

    raise InvalidDaily, message: "undefined method 'to_h' for an instance of #{type}"
  end
end
