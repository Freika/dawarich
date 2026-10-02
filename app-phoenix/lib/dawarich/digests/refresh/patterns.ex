defmodule Dawarich.Digests.Refresh.Patterns do
  @moduledoc false
  @periods ~w(night morning afternoon evening)
  @north [
    {"winter", [12, 1, 2]},
    {"spring", [3, 4, 5]},
    {"summer", [6, 7, 8]},
    {"fall", [9, 10, 11]}
  ]
  @south [
    {"winter", [6, 7, 8]},
    {"spring", [9, 10, 11]},
    {"summer", [12, 1, 2]},
    {"fall", [3, 4, 5]}
  ]

  def time_of_day(repo, user_id, first, last, zone) do
    rows =
      repo.query!(
        """
        SELECT CASE WHEN EXTRACT(HOUR FROM(to_timestamp(timestamp) AT TIME ZONE $1)) BETWEEN 0 AND 5 THEN 'night'
               WHEN EXTRACT(HOUR FROM(to_timestamp(timestamp) AT TIME ZONE $1)) BETWEEN 6 AND 11 THEN 'morning'
               WHEN EXTRACT(HOUR FROM(to_timestamp(timestamp) AT TIME ZONE $1)) BETWEEN 12 AND 17 THEN 'afternoon'
               ELSE 'evening' END,COUNT(*)
        FROM points WHERE user_id=$2 AND timestamp >= $3 AND timestamp <= $4 GROUP BY 1
        """,
        [zone, user_id, first, last]
      ).rows

    percentages(Enum.map(rows, fn [key, count] -> {key, count} end), @periods)
  end

  def percentages(rows, keys) do
    total = rows |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    for key <- keys, into: %{} do
      count =
        case List.keyfind(rows, key, 0) do
          nil -> 0
          {_, n} -> n
        end

      {key, if(total == 0, do: 0, else: round(count / total * 100))}
    end
  end

  def seasons(stats, south) do
    distances =
      for {season, months} <- if(south, do: @south, else: @north) do
        {season,
         stats
         |> Enum.filter(&(&1["month"] in months))
         |> Enum.map(& &1["distance"])
         |> Enum.sum()}
      end

    percentages(distances, ~w(winter spring summer fall))
  end
end
