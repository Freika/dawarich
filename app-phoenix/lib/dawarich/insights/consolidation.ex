defmodule Dawarich.Insights.Consolidation do
  @moduledoc false
  alias Dawarich.{Repo, Stats}
  alias Dawarich.Insights.{DistanceRace, YearRoutes}

  def load(scope, period, rows, params, opts) do
    if period.all_time do
      {:ok, index} = Stats.Pages.index(scope, Map.take(params, ~w(page places_page)), opts)

      years =
        rows
        |> Enum.map(& &1.year)
        |> Enum.uniq()
        |> Enum.sort(:desc)
        |> Enum.take(6)
        |> MapSet.new()

      years =
        Enum.filter(index.years, &MapSet.member?(years, &1.year))
        |> Enum.filter(&YearRoutes.any?(scope, %{period | year: &1.year}))
        |> Enum.map(& &1.year)

      %{
        style: Dawarich.UserSettings.get(scope.user)["maps_maplibre_style"] || "light",
        index: index,
        map_years: years,
        months: [],
        race: nil,
        prior: false
      }
    else
      selected = Enum.filter(rows, &(&1.year == period.year))

      months =
        for month <- 1..12 do
          stat = Enum.find(selected, &(&1.month == month))

          %{
            month: month,
            empty: is_nil(stat),
            distance: if(stat, do: stat.distance, else: 0),
            locked: not Stats.in_window?(%{year: period.year, month: month}, period.cutoff)
          }
        end

      [[prior]] =
        Repo.query!(
          "SELECT EXISTS(SELECT 1 FROM stats WHERE user_id=$1 AND year=$2)",
          [scope.user.id, period.year - 1],
          log: false
        ).rows

      %{
        index: nil,
        map_years: [],
        months: months,
        prior: prior,
        race: if(!period.restricted, do: DistanceRace.build(rows, period.year, period.today))
      }
    end
  end
end
