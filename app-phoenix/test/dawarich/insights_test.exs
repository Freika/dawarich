defmodule Dawarich.InsightsTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Insights, Repo, Stats}
  alias Dawarich.Insights.Heatmap
  alias Dawarich.Test.{RailsUser, StatsSeeds}

  @corpus "test/fixtures/settings_corpus.json" |> File.read!() |> Jason.decode!()
  @now ~U[2026-09-26 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    user =
      RailsUser.insert!(%{
        id: 5392,
        email: "a5s3-ins@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: user}
  end

  defp stat(user, id, year, month, distance, daily, toponyms \\ []) do
    StatsSeeds.stat!(user.id, %{
      id: id,
      year: year,
      month: month,
      distance: distance,
      daily_distance: daily,
      toponyms: toponyms,
      created_at: ~N[2026-09-20 10:00:00],
      updated_at: ~N[2026-09-20 10:00:00]
    })
  end

  defp page(user, params, overrides \\ %{}) do
    context = Map.merge(Stats.context(user, @now, true), overrides)
    Insights.page(user, params, context)
  end

  for %{"year" => year} = entry <- @corpus["heatmap"] do
    @entry entry
    test "the heatmap of #{year} matches Rails' calculator and helpers" do
      entry = @entry
      today = Date.from_iso8601!(entry["today"])

      stats =
        for s <- entry["stats"],
            do: %{year: entry["year"], month: s["month"], daily_distance: s["daily_distance"]}

      heatmap = Heatmap.build(stats, entry["year"], today)
      weeks = Heatmap.weeks(entry["year"])

      assert heatmap.daily == entry["daily_data"]

      assert Map.new(heatmap.levels, fn {k, v} -> {to_string(k), v} end) ==
               entry["activity_levels"]

      assert heatmap.active_days == entry["active_days"]
      assert heatmap.current_streak == entry["current_streak"]
      assert heatmap.longest_streak == entry["longest_streak"]
      assert iso(heatmap.longest_start) == entry["longest_streak_start"]
      assert iso(heatmap.longest_end) == entry["longest_streak_end"]
      assert [iso(hd(weeks)), iso(List.last(weeks)), length(weeks)] == entry["weeks"]

      assert Heatmap.month_labels(weeks, entry["year"], "en") ==
               Enum.map(entry["month_labels"], &%{index: &1["index"], name: &1["name"]})

      assert Heatmap.most_recent(heatmap.daily) == entry["most_recent"]

      assert Map.new(heatmap.daily, fn {k, v} -> {k, Heatmap.level(v, heatmap.levels)} end) ==
               entry["levels"]
    end
  end

  defp iso(nil), do: nil
  defp iso(date), do: Date.to_iso8601(date)

  test "a streak that ended yesterday is still the current streak, as Rails counts it" do
    stats = [%{year: 2026, month: 9, daily_distance: [[24, 5], [25, 5]]}]
    assert Heatmap.build(stats, 2026, ~D[2026-09-26]).current_streak == 2
    assert Heatmap.build(stats, 2026, ~D[2026-09-27]).current_streak == 0
  end

  test "the default year is the newest year with stats, then the local current year", %{
    user: user
  } do
    assert %{year: 2026, selected: "2026", available: []} = page(user, %{})
    stat(user, 53_921, 2023, 7, 20_000, [[14, 20_000]])

    stat(user, 53_922, 2024, 3, 38_400, [[5, 10_000], [6, 28_400]], [
      StatsSeeds.toponym("Germany", ["Berlin"])
    ])

    stat(user, 53_923, 2024, 13, 99_000, [[1, 99_000]])

    assert %{year: 2024, available: [2024, 2023], totals: totals, heatmap: %{active_days: 2}} =
             page(user, %{})

    assert totals == %{distance: 38, countries: 1, cities: 1, days: 2, any: true}
  end

  test "All Time sums every scoped year and has no heatmap", %{user: user} do
    stat(user, 53_924, 2023, 7, 20_000, [[14, 20_000]])
    stat(user, 53_925, 2024, 3, 30_000, %{"5" => 30_000})

    assert %{
             all_time: true,
             selected: "all",
             year: nil,
             heatmap: nil,
             totals: %{distance: 50, days: 2}
           } =
             page(user, %{"year" => "all"})
  end

  test "a restricted user sees years outside the window locked and gets no totals for them", %{
    user: user
  } do
    stat(user, 53_926, 2024, 6, 30_000, [[2, 30_000]])
    stat(user, 53_927, 2025, 10, 8_000, [[3, 8_000]])

    assert %{year_locked: true, locked: [2024]} =
             locked = page(user, %{"year" => "2024"}, %{restricted: true, cutoff: {2025, 9}})

    refute Map.has_key?(locked, :totals)

    assert %{year: 2025, year_locked: false, totals: %{distance: 8}} =
             page(user, %{}, %{restricted: true, cutoff: {2025, 9}})
  end

  test "malformed input: a NULL or unpaired daily_distance, a non-string year, a year beyond the calendar",
       %{user: user} do
    stat(user, 53_928, 2024, 3, 1_000, nil)
    stat(user, 53_929, 2024, 4, 2_000, [[1, 2_000], 7, [2]])

    assert %{year: 2024, totals: %{days: 1}, heatmap: %{active_days: 1}} =
             page(user, %{"year" => ["2024"]})

    assert %{year: 0, totals: %{any: false}} = page(user, %{"year" => "abc"})
    assert_raise DawarichWeb.NotFoundError, fn -> page(user, %{"year" => "99999"}) end
  end

  test "a year before 1583 renders with Elixir's calendar, unlike Rails' Julian one (ED-164)",
       %{user: user} do
    assert %{year: 1500, totals: %{any: false}} = page(user, %{"year" => "1500"})
  end
end
