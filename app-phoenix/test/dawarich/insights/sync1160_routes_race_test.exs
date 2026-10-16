defmodule Dawarich.Insights.Sync1160RoutesRaceTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts.Scope
  alias Dawarich.Insights.{DistanceRace, YearRoutes}
  alias Dawarich.Test.FrameSeeds

  defp track!(owner, id, start, path) do
    FrameSeeds.track!(owner, id, %{start_at: start, end_at: NaiveDateTime.add(start, 600)})
    rows("UPDATE tracks SET original_path=ST_GeomFromText($1,4326) WHERE id=$2", [path, id])
  end

  @now ~U[2026-10-16 12:00:00Z]

  test "year routes use local bounds owner isolation precision and dense simplification" do
    user = FrameSeeds.user!(91610, %{"timezone" => "Europe/Berlin"})
    foreign = FrameSeeds.user!(91611)

    for {owner, id, start, path} <- [
          {user.id, 916_101, ~U[2024-12-31 23:30:00Z], "LINESTRING(13.123456 52,14 53)"},
          {user.id, 916_102, ~U[2025-12-31 23:30:00Z], "LINESTRING(80 40,81 41)"},
          {foreign.id, 916_103, ~U[2025-05-01 12:00:00Z], "LINESTRING(70 40,71 41)"}
        ],
        do: track!(owner, id, DateTime.to_naive(start), path)

    scope = Scope.for_user(user, "en")

    assert {:ok, %{lines: lines}} =
             YearRoutes.fetch(scope, "2025",
               now: @now,
               self_hosted: true,
               command: fn _ -> {:error, :offline} end
             )

    assert lines == [[[13.1235, 52], [14, 53]]]
    dense = for i <- 0..2000, do: "#{13 + i * 0.001} #{52 + :math.sin(i / 50) * 0.01}"
    track!(user.id, 916_104, ~N[2025-03-01 12:00:00], "LINESTRING(#{Enum.join(dense, ",")})")

    assert {:ok, %{lines: dense_lines}} =
             YearRoutes.fetch(scope, "2025",
               now: @now,
               self_hosted: true,
               command: fn _ -> {:error, :offline} end
             )

    assert Enum.sum(Enum.map(dense_lines, &length/1)) < 500

    assert YearRoutes.within_cap([List.duplicate([1, 2], 4001), [[1, 2], [3, 4]]]) == [
             [[1, 2], [3, 4]]
           ]

    assert YearRoutes.lines(%{
             "type" => "GeometryCollection",
             "geometries" => [
               %{"type" => "LineString", "coordinates" => [[179, 1], [-179, 2]]},
               %{"type" => "Point", "coordinates" => [1, 2]}
             ]
           }) == [[[179, 1], [-179, 2]]]
  end

  test "route successes cache a day failures an hour and track edits deletes zone and plan invalidate" do
    user = FrameSeeds.user!(91612)

    FrameSeeds.track!(user.id, 916_121, %{
      start_at: ~N[2025-03-01 12:00:00],
      end_at: ~N[2025-03-01 13:00:00],
      path: "LINESTRING(13 52,14 53)"
    })

    scope = Scope.for_user(user, "en")
    {:ok, cache} = Agent.start_link(fn -> %{} end)
    on_exit(fn -> if Process.alive?(cache), do: Agent.stop(cache) end)
    owner = self()

    command = fn
      ["GET", key] ->
        {:ok, Agent.get(cache, &Map.get(&1, key))}

      ["SET", key, value, "EX", ttl] ->
        send(owner, {:ttl, ttl})
        Agent.update(cache, &Map.put(&1, key, value))
        {:ok, "OK"}
    end

    read = fn _, _ ->
      send(owner, :query)
      [[[13, 52], [14, 53]]]
    end

    opts = [now: @now, self_hosted: true, command: command, read: read]
    for _ <- 1..2, do: assert({:ok, %{lines: [_]}} = YearRoutes.fetch(scope, "2025", opts))
    assert_receive :query
    assert_receive {:ttl, "86400"}
    refute_receive :query
    rows("UPDATE tracks SET updated_at=updated_at+interval '1 second' WHERE id=916121")

    failed =
      Keyword.put(opts, :read, fn _, _ ->
        send(owner, :failed_query)
        raise "synthetic route failure"
      end)

    for _ <- 1..2, do: assert({:ok, %{lines: []}} = YearRoutes.fetch(scope, "2025", failed))
    assert_receive :failed_query
    assert_receive {:ttl, "3600"}
    refute_receive :failed_query

    rows(
      "UPDATE users SET settings=jsonb_set(settings,'{timezone}','\"Asia/Tokyo\"') WHERE id=$1",
      [user.id]
    )

    assert {:ok, %{lines: [_]}} = YearRoutes.fetch(scope, "2025", opts)
    assert_receive :query
    rows("DELETE FROM tracks WHERE id=916121")
    assert {:ok, %{lines: [_]}} = YearRoutes.fetch(scope, "2025", opts)
    assert_receive :query
    rows("UPDATE users SET plan=0 WHERE id=$1", [user.id])

    assert {:ok, %{lines: []}} =
             YearRoutes.fetch(scope, "2024", Keyword.put(opts, :self_hosted, false))

    refute_receive :query
  end

  test "distance race aligns leap days stops at local today and omits missing or future comparisons" do
    rows = [
      %{year: 2024, month: 2, daily_distance: [[28, 1000], [29, 3000]]},
      %{year: 2024, month: 3, daily_distance: [[1, 2000]]},
      %{year: 2025, month: 3, daily_distance: [[1, 9000]]}
    ]

    race = DistanceRace.build(rows, 2025, ~D[2025-03-01])
    assert length(race.current) == 60
    assert length(race.previous) == 365
    assert race.lead == 3000

    leap =
      DistanceRace.build(
        [%{year: 2023, month: 2, daily_distance: [[28, 2000]]}],
        2024,
        ~D[2024-02-29]
      )

    assert Enum.slice(leap.previous, 58, 2) == [2000, 2000]
    assert length(leap.current) == 60
    assert DistanceRace.build(rows, 2026, ~D[2025-03-01]) == nil
    assert DistanceRace.build(rows, 2023, ~D[2025-03-01]).previous == nil
    assert DistanceRace.build(rows, 2023, ~D[2025-03-01]).lead == nil
  end
end
