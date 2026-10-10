defmodule Dawarich.Stats.HeatmapTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Stats.Heatmap

  @today ~D[2026-09-26]

  defp stat(year, month, stored) do
    {:ok, pairs} = Heatmap.pairs(stored)
    %{year: year, month: month, daily: pairs}
  end

  defp json(term), do: term |> Ruby.json() |> IO.iodata_to_binary()

  test "a Hash daily_distance: dates in stored order, zero days kept, invalid days skipped, Rails' percentiles and the first longest streak" do
    stats = [
      stat(2024, 1, {:object, [{"1", 1000}, {"2", 0}, {"3", 3000.9}, {"31", 500}]}),
      stat(2024, 2, {:object, [{"1", 2000}, {"5", 100}, {"6", 200}, {"30", 9}]})
    ]

    assert json(Heatmap.term(stats, 2024, @today)) ==
             ~s({"dailyData":{"2024-01-01":1000,"2024-01-02":0,"2024-01-03":3000,"2024-01-31":500,"2024-02-01":2000,"2024-02-05":100,"2024-02-06":200},) <>
               ~s("activityLevels":{"p25":200,"p50":1000,"p75":2000,"p90":3000},"maxDistance":3000,"activeDays":6,) <>
               ~s("currentStreak":0,"longestStreak":2,"longestStreakStart":"2024-01-31","longestStreakEnd":"2024-02-01"})
  end

  test "an Array daily_distance is to_h'd: a repeated key keeps its first position and its last value; 1 and \"1\" are different keys" do
    stats = [stat(2024, 3, [[2, 100], [1, 50], [2, 300], ["1", 7]])]

    assert json(Heatmap.term(stats, 2024, @today)) =~
             ~s({"dailyData":{"2024-03-02":300,"2024-03-01":57},)
  end

  test "the current streak counts back from today in the current year, else from the day before" do
    all = stat(2026, 9, {:object, [{"24", 1}, {"25", 1}, {"26", 1}]})
    before = stat(2026, 9, {:object, [{"24", 1}, {"25", 1}]})
    assert %{"currentStreak" => 3} = Jason.decode!(json(Heatmap.term([all], 2026, @today)))
    assert %{"currentStreak" => 2} = Jason.decode!(json(Heatmap.term([before], 2026, @today)))
  end

  test "no stats give ActivityHeatmapCalculator's empty result" do
    assert json(Heatmap.term([], 2024, @today)) ==
             ~s({"dailyData":{},"activityLevels":{"p25":1000,"p50":5000,"p75":10000,"p90":20000},"maxDistance":0,"activeDays":0,) <>
               ~s("currentStreak":0,"longestStreak":0,"longestStreakStart":null,"longestStreakEnd":null})
  end

  test "pairs/1 owns what Rails reads unambiguously and hands the rest to Puma" do
    assert Heatmap.pairs({:object, [{"1", nil}, {"02", 5.9}]}) ==
             {:ok, [{"1", 1, 0}, {"02", 2, 5}]}

    for stored <- [
          nil,
          "x",
          5,
          [[1]],
          [[1, 2, 3]],
          [1],
          {:object, [{"-1", 5}]},
          {:object, [{"1.5", 5}]},
          {:object, [{"1", "12"}]},
          {:object, [{"1", true}]},
          [[1.5, 3]],
          [[nil, 3]],
          [[-1, 3]]
        ],
        do: assert({:replay, _} = Heatmap.pairs(stored), inspect(stored))
  end
end
