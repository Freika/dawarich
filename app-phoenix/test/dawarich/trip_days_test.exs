defmodule Dawarich.TripDaysTest do
  use ExUnit.Case, async: true

  alias Dawarich.TripDays

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  describe "local spans and trip_duration" do
    test "local times in the request zone and the length of the borrowed month, DST included" do
      assert TripDays.local_span(
               ~N[2026-03-20 09:00:00],
               ~N[2026-04-10 07:00:00],
               "Europe/Berlin"
             ) == %{
               started_local: ~N[2026-03-20 10:00:00.000000],
               ended_local: ~N[2026-04-10 09:00:00.000000],
               previous_month_days: 30,
               near_transition: false
             }

      assert %{previous_month_days: 31, near_transition: false} =
               TripDays.local_span(~N[2026-03-20 09:00:00], ~N[2026-04-10 07:00:00], "Etc/UTC")
    end

    test "a previous-month wall time within a day of an offset change is flagged: a spring-forward gap and a fall-back overlap" do
      assert %{near_transition: true} =
               TripDays.local_span(
                 ~N[2026-03-30 08:00:00],
                 ~N[2026-04-29 00:30:00],
                 "Europe/Berlin"
               )

      assert %{near_transition: true} =
               TripDays.local_span(
                 ~N[2026-10-28 08:00:00],
                 ~N[2026-11-25 01:30:00],
                 "Europe/Berlin"
               )

      assert %{near_transition: false} =
               TripDays.local_span(
                 ~N[2026-10-28 08:00:00],
                 ~N[2026-11-25 01:30:00],
                 "Asia/Kathmandu"
               )
    end

    test "Rails' borrowing: hours from days, days from the previous month once, months from years" do
      assert TripDays.duration_parts(~N[2026-01-31 10:00:00], ~N[2026-02-02 08:00:00], 31) ==
               {[{"days", 1}, {"hours", 22}], true}

      assert TripDays.duration_parts(~N[2026-01-31 10:00:00], ~N[2026-03-02 08:00:00], 28) ==
               {[{"months", 1}, {"hours", 22}], true}

      assert TripDays.duration_parts(~N[2026-02-15 13:00:00], ~N[2027-04-18 18:00:00], 31) ==
               {[{"years", 1}, {"months", 2}, {"days", 3}, {"hours", 5}], false}

      assert TripDays.duration_parts(~N[2026-06-01 10:00:00], ~N[2026-06-01 10:59:00], 31) ==
               {[], false}
    end
  end

  alias Dawarich.Test.TripsSeeds

  describe "day data" do
    setup do
      TripsSeeds.user!(8821, %{"timezone" => "UTC"})
      TripsSeeds.user!(8822)
      TripsSeeds.source!(88_201, "watch")
      midnight = 1_767_312_000

      for {minute, i} <- Enum.with_index([-10, 30, 35, 40]) do
        TripsSeeds.point!(%{
          id: 882_100 + i,
          user_id: 8821,
          timestamp: midnight + minute * 60,
          at: [12.37 + minute * 0.001, 51.34],
          tracker_id: "phone"
        })
      end

      for {minute, i} <- Enum.with_index([5, 10]) do
        TripsSeeds.point!(%{
          id: 882_200 + i,
          user_id: 8821,
          timestamp: midnight + minute * 60,
          at: [12.37 + minute * 0.001, 51.34],
          source_id: 88_201
        })
      end

      TripsSeeds.point!(%{
        id: 882_300,
        user_id: 8821,
        timestamp: midnight + 20 * 60,
        at: [12.39, 51.36],
        tracker_id: "phone",
        anomaly: true
      })

      TripsSeeds.point!(%{
        id: 882_302,
        user_id: 8821,
        timestamp: midnight + 45 * 60,
        at: [12.395, 51.365],
        tracker_id: "phone",
        anomaly: true
      })

      TripsSeeds.point!(%{
        id: 882_301,
        user_id: 8822,
        timestamp: midnight + 1 * 60,
        at: [12.37, 51.34],
        tracker_id: "phone"
      })

      %{from: midnight - 3600, to: midnight + 86_400}
    end

    test "a 60-minute gap keeps the phone as the only primary device (Rails' recording-gap spec)",
         ctx do
      days = TripDays.day_data(8821, ctx.from, ctx.to, 3600, "Etc/UTC")

      assert days.windows_json ==
               ~S([{"tracker_id":"phone","start_at":1767311400,"end_at":1767314400}])

      assert days.stats[~D[2026-01-02]].first == ~N[2026-01-02 00:30:00]
      assert days.stats[~D[2026-01-01]].first == ~N[2026-01-01 23:50:00]
    end

    test "a 10-minute gap lets the watch fill the phone's hole; anomalies and other users never count",
         ctx do
      %{stats: stats} = TripDays.day_data(8821, ctx.from, ctx.to, 600, "Etc/UTC")
      assert stats[~D[2026-01-02]].first == ~N[2026-01-02 00:05:00]
      assert stats[~D[2026-01-02]].last == ~N[2026-01-02 00:40:00]
      refute stats[~D[2026-01-02]].first == ~N[2026-01-02 00:01:00]
    end

    test "days are local to timezone_iana: a point after local midnight belongs to the next day" do
      TripsSeeds.user!(8823)

      TripsSeeds.point!(%{
        id: 882_401,
        user_id: 8823,
        timestamp: 1_736_942_400,
        at: [12.37, 51.34]
      })

      TripsSeeds.point!(%{
        id: 882_402,
        user_id: 8823,
        timestamp: 1_736_983_800,
        at: [12.376, 51.346]
      })

      %{stats: stats} =
        TripDays.day_data(8823, 1_736_899_200, 1_737_071_999, 1800, "Europe/Berlin")

      assert stats[~D[2025-01-16]].first == ~N[2025-01-16 00:30:00]
      assert stats |> Map.keys() |> Enum.sort(Date) == [~D[2025-01-15], ~D[2025-01-16]]
    end

    test "a day's distance is PostGIS' geodesic length of its line" do
      TripsSeeds.user!(8824, %{"timezone" => "UTC"})

      TripsSeeds.point!(%{
        id: 882_501,
        user_id: 8824,
        timestamp: 1_780_000_000,
        at: [12.35, 51.33]
      })

      TripsSeeds.point!(%{
        id: 882_502,
        user_id: 8824,
        timestamp: 1_780_003_600,
        at: [12.35, 51.34]
      })

      %{stats: stats} = TripDays.day_data(8824, 1_779_990_000, 1_780_010_000, 1800, "Etc/UTC")
      [%{distance_m: meters}] = Map.values(stats)
      assert_in_delta meters, 1112.5, 2.0
    end
  end

  test "the windows' JSON is Rails': key order kept, <, > and & escaped as Oj writes them" do
    assert TripDays.windows_json([{"<b>&", 1, 2}]) ==
             ~S([{"tracker_id":"\u003cb\u003e\u0026","start_at":1,"end_at":2}])

    assert TripDays.windows_json([]) == "[]"
  end
end
