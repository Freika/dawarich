defmodule Dawarich.Stats.Summary do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.Stats.{PointCounts, Toponyms}

  @months ~w(january february march april may june july august september october november december)

  def term(user_id, store_geodata, now) do
    stats =
      for [year, month, distance, toponyms] <-
            Repo.query!("SELECT year, month, distance, toponyms FROM stats WHERE user_id = $1", [
              user_id
            ]).rows,
          do: %{
            year: year,
            month: month,
            distance: distance,
            toponyms: Toponyms.sanitize(toponyms)
          }

    [[points]] = Repo.query!("SELECT points_count FROM users WHERE id = $1", [user_id]).rows
    toponyms = Enum.flat_map(stats, & &1.toponyms)

    {:object,
     [
       {"totalDistanceKm", km(total(stats))},
       {"totalPointsTracked", points},
       {"totalReverseGeocodedPoints", PointCounts.fetch(user_id, store_geodata, now).geocoded},
       {"totalCountriesVisited", length(Toponyms.countries(toponyms))},
       {"totalCitiesVisited", length(Toponyms.cities(toponyms))},
       {"yearlyStats", yearly(stats)}
     ]}
  end

  defp yearly(stats) do
    for {year, rows} <- stats |> Enum.group_by(& &1.year) |> Enum.sort_by(&elem(&1, 0), :desc) do
      visited = rows |> Enum.flat_map(& &1.toponyms) |> Toponyms.visited()

      {:object,
       [
         {"year", year},
         {"totalDistanceKm", km(total(rows))},
         {"totalCountriesVisited", length(Toponyms.countries(visited))},
         {"totalCitiesVisited", length(Toponyms.cities(visited))},
         {"monthlyDistanceKm",
          {:object,
           for(
             {name, month} <- Enum.with_index(@months, 1),
             do: {name, km(month_distance(rows, month))}
           )}}
       ]}
    end
  end

  defp month_distance(rows, month),
    do: Enum.find_value(rows, 0, &(&1.month == month && &1.distance))

  defp total(rows), do: rows |> Enum.map(& &1.distance) |> Enum.sum()
  defp km(meters), do: Integer.floor_div(meters, 1000)
end
