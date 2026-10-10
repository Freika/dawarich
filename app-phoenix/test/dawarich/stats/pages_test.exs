defmodule Dawarich.Stats.PagesTest do
  use Dawarich.DataCase, async: true
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Accounts.Scope
  alias Dawarich.Stats.Pages
  alias Dawarich.Test.FrameSeeds
  @now ~U[2026-02-28 23:30:00Z]
  setup do
    user = FrameSeeds.user!(8611, %{"timezone" => "Pacific/Kiritimati"}, %{plan: 0})
    %{scope: Scope.for_user(user, "de")}
  end

  test "analytics periods retain source casts windows and owner-local month edges", %{
    scope: scope
  } do
    stat!(scope.user.id, %{year: 2025, month: 2, distance: 1000, daily_distance: [[1, 1000]]})

    stat!(scope.user.id, %{
      year: 2025,
      month: 3,
      distance: 3000,
      daily_distance: [[1, 1000], [2, 2000]]
    })

    stat!(scope.user.id, %{year: 2025, month: 4, distance: 9000, daily_distance: [[1, 9000]]})
    assert {:ok, year} = Pages.year(scope, %{"year" => "2025tail"}, now: @now, self_hosted: false)
    assert year.year == 2025
    assert Enum.map(year.stats, & &1.month) == [3, 4]
    assert Enum.slice(year.distances, 1, 3) == [1000, 3000, 9000]

    assert {:ok, month} =
             Pages.month(scope, %{"year" => "2025tail", "month" => "4tail"},
               now: @now,
               self_hosted: false
             )

    assert month.data.previous.distance == 3000
    assert month.data.average_km == 6
    assert month.peak == {1, 9000}
    assert elem(month.bounds, 0) == "2025-04-01 00:00:00 +1400"

    assert {:ok, locked} =
             Pages.month(scope, %{"year" => "2025", "month" => "2"},
               now: @now,
               self_hosted: false
             )

    assert locked.data.stat == nil

    assert {:error, :invalid_input} =
             Pages.year(scope, %{"year" => []}, now: @now, self_hosted: true)
  end

  test "analytics query cannot return another owner's summaries", %{scope: scope} do
    foreign = FrameSeeds.user!(8612)

    stat!(scope.user.id, %{
      year: 2025,
      month: 3,
      distance: 3000,
      toponyms: [toponym("Germany", ["Berlin"])],
      daily_distance: [[1, 3000]]
    })

    stat!(foreign.id, %{
      year: 2025,
      month: 3,
      distance: 99000,
      toponyms: [toponym("France", ["Paris"])]
    })

    assert {:ok, page} = Pages.year(scope, %{"year" => "2025"}, now: @now, self_hosted: true)
    assert Enum.sum(page.distances) == 3000
    assert Enum.flat_map(page.stats, & &1.toponyms) |> Enum.map(& &1["country"]) == ["Germany"]
    assert {:ok, index} = Pages.index(scope, %{}, now: @now, self_hosted: true)
    assert index.total_distance == 3000
    assert index.countries_visited == ["Germany"]
    assert index.points.state == :pending

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password='changed-session-00000000000000000' WHERE id=$1",
      [scope.user.id], log: false)

    assert {:error, :stale_session} =
             Pages.year(scope, %{"year" => "2025"}, now: @now, self_hosted: true)
  end

  test "analytics yearly collections stay bounded with explicit navigation and full totals", %{
    scope: scope
  } do
    for year <- 1950..2010, do: stat!(scope.user.id, %{year: year, month: 1, distance: 1000})
    assert {:ok, first} = Pages.index(scope, %{}, now: @now, self_hosted: false)
    assert length(first.years) + length(first.locked_years) == 50
    assert first.total_distance == 61000
    assert first.total_pages == 2
    assert first.more == true
    assert {:ok, second} = Pages.index(scope, %{"page" => "2"}, now: @now, self_hosted: false)
    assert length(second.years) + length(second.locked_years) == 11
    assert second.more == false
    assert MapSet.disjoint?(MapSet.new(first.locked_years), MapSet.new(second.locked_years))
  end
end
