defmodule Dawarich.Insights.ResidencyPage do
  @moduledoc false
  alias Dawarich.{Repo, Residency, RubyInteger}
  alias Dawarich.Analytics.Period

  @days """
  WITH days AS (
    SELECT DATE(to_timestamp(timestamp) AT TIME ZONE 'UTC') AS day,country_name,count(*) AS points
    FROM points WHERE user_id=$1 AND timestamp BETWEEN $2 AND $3
      AND country_name IS NOT NULL AND country_name!='' AND anomaly IS NOT TRUE
    GROUP BY day,country_name
  )
  """

  def load(scope, params, opts) do
    with {:ok, scope, period} <- Period.admit(scope, params, :insights, opts),
         false <- period.restricted or period.all_time,
         {:ok, {year, first, last}} <-
           Residency.local_window(
             scope.user.id,
             period.year,
             %{"timezone" => period.zone},
             period.today
           ) do
      page = max(1, min(RubyInteger.to_i(params["residency_page"] || "1"), 1_000_000_000_000))
      args = [scope.user.id, first, last]

      daily =
        Repo.query!(
          @days <>
            "SELECT DISTINCT ON(day) day,country_name FROM days ORDER BY day,points DESC,country_name COLLATE \"C\"",
          args,
          log: false
        ).rows

      countries =
        Repo.query!(
          @days <>
            "SELECT country_name,array_agg(day ORDER BY day),count(*) OVER() FROM days GROUP BY country_name ORDER BY count(*) DESC,country_name COLLATE \"C\" LIMIT 50 OFFSET $4",
          args ++ [(page - 1) * 50],
          log: false
        ).rows

      total = length(daily)

      count =
        case countries do
          [[_, _, count] | _] -> count
          _ -> 0
        end

      {:ok,
       %{
         state: :ready,
         zone: period.zone,
         today: period.today,
         country_count: count,
         year: year,
         total: total,
         daily: daily,
         page: page,
         more: count > page * 50,
         countries:
           for(
             [name, days, _] <- countries,
             do: %{
               name: name,
               days: length(days),
               periods: periods(days),
               warning: length(days) >= 183,
               iso: elem(Dawarich.CountryNames.iso_codes(name), 0),
               year_percentage:
                 Dawarich.RubyFloat.round(
                   length(days) / if(Calendar.ISO.leap_year?(year), do: 366, else: 365) * 100,
                   1
                 )
             }
           )
       }}
    else
      true -> {:ok, %{state: :restricted}}
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp periods([]), do: []

  defp periods([first | rest]) do
    {first, last, acc} =
      Enum.reduce(rest, {first, first, []}, fn date, {first, last, acc} ->
        if Date.diff(date, last) == 1,
          do: {first, date, acc},
          else: {date, date, [{first, last} | acc]}
      end)

    Enum.reverse([{first, last} | acc])
  end
end
