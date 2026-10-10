defmodule Dawarich.Insights.PagesTest do
  use Dawarich.DataCase, async: false
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Accounts.Scope
  alias Dawarich.Insights.Pages
  alias Dawarich.Test.{FrameSeeds, NativeAdminUI}
  @now ~U[2026-10-03 10:00:00Z]
  setup do
    user = FrameSeeds.user!(8621)

    for {year, month} <- [{2024, 1}, {2025, 3}, {2025, 4}] do
      stat!(user.id, %{
        year: year,
        month: month,
        distance: 1000,
        daily_distance: [[1, 1000]],
        toponyms: [toponym("Germany", ["Berlin"])]
      })
    end

    %{scope: Scope.for_user(user, "de")}
  end

  test "all-time and restricted requests do not request patterns", %{scope: scope} do
    {{:ok, all}, queries} =
      NativeAdminUI.queries(fn ->
        Pages.details(scope, %{"year" => "all"}, now: @now, self_hosted: true)
      end)

    assert all.all_time == true
    assert all.totals.distance == 3
    refute Enum.any?(queries, &String.contains?(&1, "FROM digests"))
    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [scope.user.id], log: false)

    {{:ok, restricted}, queries} =
      NativeAdminUI.queries(fn ->
        Pages.details(scope, %{"year" => "2025"}, now: @now, self_hosted: false)
      end)

    assert restricted.state == :restricted
    refute Enum.any?(queries, &String.contains?(&1, "FROM digests"))
  end

  test "native Insights keeps source defaults and refuses malformed daily data without effects",
       %{scope: scope} do
    assert {:ok, overview} = Pages.overview(scope, %{}, now: @now, self_hosted: true)
    assert overview.year == 2025
    assert overview.selected_month == 4
    assert map_size(overview.heatmap.daily) <= 366

    assert {:ok, details} =
             Pages.details(scope, %{"year" => "2025", "month" => "3tail"},
               now: @now,
               self_hosted: true
             )

    assert details.state == :pending
    assert details.selected_month == 3

    assert Dawarich.Repo.query!("SELECT count(*) FROM digests WHERE user_id=$1", [scope.user.id],
             log: false
           ).rows == [[0]]

    assert {:error, :invalid_input} =
             Pages.overview(scope, %{"year" => %{}}, now: @now, self_hosted: true)

    Dawarich.Repo.query!(
      "UPDATE stats SET daily_distance=$1 WHERE user_id=$2 AND month=3",
      [[[1, 1000], "malformed"], scope.user.id],
      log: false
    )

    assert {:error, :invalid_input} =
             Pages.overview(scope, %{"year" => "2025"}, now: @now, self_hosted: true)
  end

  test "native ready details preserve source activity and monthly projections without private metadata",
       %{scope: scope} do
    [[updated]] =
      Dawarich.Repo.query!("SELECT max(updated_at) FROM stats WHERE user_id=$1", [scope.user.id],
        log: false
      ).rows

    stamp = NaiveDateTime.add(updated, 1)

    digest!(scope.user.id, %{
      year: 2025,
      updated_at: stamp,
      travel_patterns: %{
        "time_of_day" => %{"morning" => 100},
        "activity_breakdown" => %{
          "walking" => %{
            "duration" => 60,
            "percentage" => 100,
            "api_key" => "synthetic-pattern-key"
          }
        },
        "seasonality" => %{"spring" => 100},
        "secret" => "synthetic-private-phrase"
      }
    })

    digest!(scope.user.id, %{
      year: 2025,
      month: 3,
      period_type: 0,
      updated_at: stamp,
      monthly_distances: %{"1" => 1000},
      travel_patterns: %{"time_of_day" => %{"morning" => 100}}
    })

    assert {:ok, page} =
             Pages.details(scope, %{"year" => "2025", "month" => "3"},
               now: @now,
               self_hosted: true
             )

    assert page.state == :ready
    assert page.activity == %{"walking" => %{"duration" => 60, "percentage" => 100}}
    assert page.monthly.distances == %{"1" => 1000}
    assert Enum.sum(page.weekly) == 1000
    refute :erlang.term_to_binary(page) =~ "synthetic-pattern-key"
    refute :erlang.term_to_binary(page) =~ "synthetic-private-phrase"
  end

  test "analytics year projections ignore another period's malformed rows", %{scope: scope} do
    stat!(scope.user.id, %{
      year: 2023,
      month: 1,
      distance: 1000,
      daily_distance: [[1, 1000], "malformed"]
    })

    assert {:ok, overview} =
             Pages.overview(scope, %{"year" => "2025"}, now: @now, self_hosted: true)

    assert overview.totals.distance == 2

    assert {:ok, details} =
             Pages.details(scope, %{"year" => "2025"}, now: @now, self_hosted: true)

    assert details.totals.distance == 2

    assert {:error, :invalid_input} =
             Pages.overview(scope, %{"year" => "all"}, now: @now, self_hosted: true)
  end
end
