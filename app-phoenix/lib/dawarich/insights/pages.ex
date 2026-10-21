defmodule Dawarich.Insights.Pages do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Analytics.Period
  alias Dawarich.{Stats, Repo, Digests}
  alias Dawarich.Insights.{Heatmap, NativeDetails, Consolidation}

  def overview(scope, params, opts \\ []) do
    with {:ok, scope} <- DataAccess.admit(scope, settings: true),
         available = available(scope.user.id),
         {:ok, scope, period} <- Period.admit(scope, params, :insights, opts, available),
         {:ok, rows} <- rows(scope.user.id, period) do
      years = Enum.uniq(Enum.map(rows, & &1.year))
      locked = if period.restricted, do: available -- years, else: []

      data = %{
        active: scope.user.status == 1,
        available: available,
        locked: locked,
        all_time: period.all_time,
        year: period.year,
        selected: if(period.all_time, do: "all", else: to_string(period.year)),
        year_locked: period.year in locked,
        restricted: period.restricted,
        unit: period.unit,
        period: period
      }

      if data.year_locked do
        {:ok, data}
      else
        selected =
          if period.all_time, do: rows, else: Enum.filter(rows, &(&1.year == period.year))

        if not Enum.all?(selected, &valid_daily?/1),
          do: raise(ArgumentError, "invalid daily projection")

        month =
          period.month ||
            selected
            |> Enum.map(& &1.month)
            |> Enum.max(fn ->
              if period.year == period.today.year, do: period.today.month, else: 12
            end)

        raw =
          Enum.map(selected, fn r ->
            %{
              "year" => r.year,
              "month" => r.month,
              "distance" => r.distance,
              "toponyms" => r.toponyms,
              "daily_distance" => r.daily_distance
            }
          end)

        totals =
          Dawarich.Insights.Details.Totals.calculate(raw, period.unit)
          |> Map.put(:any, selected != [])

        {:ok,
         Map.merge(data, %{
           selected_month: month,
           totals: totals,
           consolidated: Consolidation.load(scope, period, rows, params, opts),
           heatmap:
             if(period.all_time,
               do: nil,
               else: Heatmap.build(selected, period.year, period.today)
             )
         })}
      end
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  def details(scope, params, opts \\ []) do
    with {:ok, scope} <- DataAccess.admit(scope, settings: true),
         available = available(scope.user.id),
         {:ok, scope, period} <- Period.admit(scope, params, :insights, opts, available),
         {:ok, rows} <- rows(scope.user.id, period) do
      selected =
        if period.all_time,
          do: rows,
          else: Enum.filter(rows, &(&1.year in [period.year, period.year - 1]))

      if period.restricted or Enum.all?(selected, &valid_daily?/1),
        do: NativeDetails.load(scope.user.id, period, rows, available),
        else: {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  defp available(id),
    do:
      Repo.query!(
        "SELECT DISTINCT year FROM stats WHERE user_id=$1 AND month BETWEEN 1 AND 12 ORDER BY year DESC",
        [id],
        log: false
      ).rows
      |> Enum.map(&hd/1)

  defp rows(id, period) do
    rows =
      Repo.query!(
        "SELECT year,month,distance,toponyms,daily_distance,updated_at FROM stats WHERE user_id=$1 AND month BETWEEN 1 AND 12 ORDER BY year,month",
        [id],
        log: false
      ).rows

    rows =
      for [year, month, distance, toponyms, daily, updated] <- rows,
          Stats.in_window?(%{year: year, month: month}, period.cutoff),
          do: %{
            year: year,
            month: month,
            distance: distance,
            toponyms: Period.narrow(toponyms),
            daily_distance: daily,
            updated_at: updated
          }

    {:ok, rows}
  end

  defp valid_daily?(row) do
    pairs =
      case row.daily_distance do
        %{} -> Enum.map(row.daily_distance, fn {day, meters} -> [day, meters] end)
        values when is_list(values) -> values
        _ -> [:invalid]
      end

    length(pairs) <= 31 and
      Enum.all?(pairs, fn
        [day, meters] ->
          day = Digests.to_i(day)

          day =
            if day < 0,
              do: Date.days_in_month(Date.new!(row.year, row.month, 1)) + day + 1,
              else: day

          match?({:ok, _}, Date.new(row.year, row.month, day)) and
            (is_number(meters) or is_binary(meters))

        _ ->
          false
      end)
  end
end
