defmodule Dawarich.ResidencyYear do
  @moduledoc false

  alias Dawarich.{LocalTime, Repo, Residency, UserTimeZone}

  def read(user, year, now) do
    settings = user.settings || %{}
    {_zone, today} = LocalTime.local(settings, now)

    with {:ok, window} <- window(year || default_year(user.id, today), settings),
         {:ok, {:object, pairs}} <- Residency.term(user.id, window) do
      result = Map.new(pairs)
      {:object, daily} = result["daily_countries"]

      {:ok,
       %{
         year: result["year"],
         days_in_year: result["days_in_year"],
         total: result["total_tracked_days"],
         countries: for({:object, fields} <- result["countries"], do: country(Map.new(fields))),
         daily: Map.new(daily),
         today: today
       }}
    end
  end

  defp window(year, settings) when year in 1970..2037 do
    %{rows: [[first, last]]} =
      UserTimeZone.query!(
        "SELECT extract(epoch FROM make_timestamptz($1, 1, 1, 0, 0, 0, z.name))::bigint, " <>
          "extract(epoch FROM make_timestamptz($1, 12, 31, 23, 59, 59, z.name))::bigint FROM z",
        [year],
        settings
      )

    {:ok, {year, first, last}}
  end

  defp window(year, _settings), do: {:replay, "residency year #{year}"}

  defp default_year(user_id, today) do
    case Repo.query!("SELECT max(year) FROM stats WHERE user_id = $1", [user_id]).rows do
      [[nil]] -> today.year
      [[year]] -> year
    end
  end

  defp country(fields) do
    %{
      name: fields["country_name"],
      iso: fields["iso_a2"],
      days: fields["days"],
      year_percentage: fields["year_percentage"],
      warning: fields["threshold_warning"],
      periods:
        for {:object, period} <- fields["periods"] do
          period = Map.new(period)

          %{
            first: Date.from_iso8601!(period["start_date"]),
            last: Date.from_iso8601!(period["end_date"]),
            days: period["consecutive_days"]
          }
        end
    }
  end
end
