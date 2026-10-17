defmodule Dawarich.Digests.Seasonality do
  @moduledoc false

  alias Dawarich.Digests.Queries

  @external_resource Path.expand("../../../priv/digest_southern_zones.json", __DIR__)
  @southern @external_resource |> File.read!() |> Jason.decode!() |> MapSet.new()
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

  def calculate(repo, context, year) do
    stats = Queries.yearly(repo, context, year)
    seasons = if MapSet.member?(@southern, context.raw_zone), do: @south, else: @north

    totals =
      Enum.map(seasons, fn {season, months} ->
        {season,
         stats
         |> Enum.filter(&(&1["month"] in months))
         |> Enum.map(& &1["distance"])
         |> Enum.sum()}
      end)

    total = Enum.sum(Enum.map(totals, &elem(&1, 1)))

    Map.new(totals, fn {season, distance} ->
      {season, if(total == 0, do: 0, else: round(distance / total * 100))}
    end)
  end
end
