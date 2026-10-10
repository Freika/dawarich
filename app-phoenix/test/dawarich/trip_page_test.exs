defmodule Dawarich.TripPageTest do
  use ExUnit.Case, async: true

  alias Dawarich.TripPage
  alias Dawarich.Test.TripsSeeds
  alias DawarichWeb.HumanDatetime

  @path [[12.37, 51.338], [12.381, 51.341]]
  @now ~U[2026-09-29 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    TripsSeeds.country!("Germany", "DE", "DEU")
    :ok
  end

  test "UTC: ISO values end in Z, timezone_iana is Etc/UTC, three local days, Rails' duration" do
    TripsSeeds.user!(8841, %{"timezone" => "UTC"})

    TripsSeeds.trip!(%{
      id: 884_101,
      user_id: 8841,
      path: @path,
      started_at: ~N[2026-06-01 22:00:00],
      ended_at: ~N[2026-06-03 01:00:00]
    })

    {:ok, page} = TripPage.load(Dawarich.Accounts.get(8841), 884_101, @now)

    assert HumanDatetime.iso8601(page.started_at) == "2026-06-01T22:00:00Z"
    assert page.iana == "Etc/UTC"
    assert Enum.map(page.days, & &1.date) == [~D[2026-06-01], ~D[2026-06-02], ~D[2026-06-03]]
    assert page.duration == [{"days", 1}, {"hours", 3}]
    assert page.path_json == ~S([[12.37,51.338],[12.381,51.341]])
    assert page.windows_json == "[]"
  end

  test "Berlin: offsets, notes by UTC date, the recalculating clock and the trip's active share only" do
    TripsSeeds.user!(8842)
    TripsSeeds.user!(8899)

    TripsSeeds.trip!(%{
      id: 884_201,
      user_id: 8842,
      path: @path,
      last_recalculated_at: DateTime.to_naive(DateTime.add(@now, -30))
    })

    TripsSeeds.trip!(%{id: 889_901, user_id: 8899, path: @path})

    TripsSeeds.note!(%{
      id: 88_421,
      trip_id: 884_201,
      user_id: 8842,
      body: "Morning",
      noted_at: ~N[2026-05-10 23:30:00]
    })

    TripsSeeds.note!(%{
      id: 88_423,
      trip_id: 884_201,
      user_id: 8842,
      attachable_type: "Place",
      body: "Another record",
      noted_at: ~N[2026-05-11 12:00:00]
    })

    TripsSeeds.note!(%{
      id: 88_422,
      trip_id: 884_201,
      user_id: 8842,
      body: "Outside",
      noted_at: ~N[2026-05-20 12:00:00]
    })

    TripsSeeds.note!(%{
      id: 88_991,
      trip_id: 889_901,
      user_id: 8899,
      body: "Foreign",
      noted_at: ~N[2026-05-09 12:00:00]
    })

    TripsSeeds.shared_link!(%{
      id: "a8510000-0000-4000-8000-0000000000a1",
      resource_type: 1,
      trip_id: 884_201,
      user_id: 8842
    })

    TripsSeeds.shared_link!(%{
      id: "a8510000-0000-4000-8000-0000000000a2",
      resource_type: 0,
      trip_id: 884_201,
      user_id: 8842,
      expires_at: ~N[2026-09-28 12:00:00]
    })

    TripsSeeds.shared_link!(%{
      id: "a8510000-0000-4000-8000-0000000000a4",
      resource_type: 0,
      trip_id: 884_201,
      user_id: 8842,
      revoked_at: ~N[2026-09-28 12:00:00]
    })

    TripsSeeds.shared_link!(%{
      id: "a8510000-0000-4000-8000-0000000000a5",
      resource_type: 0,
      trip_id: 889_901,
      user_id: 8899
    })

    user = Dawarich.Accounts.get(8842)
    {:ok, page} = TripPage.load(user, 884_201, @now)

    assert HumanDatetime.iso8601(page.started_at) == "2026-05-09T08:00:00+02:00"
    assert page.recalculating
    refute page.shared

    assert [%{note: nil}, %{note: %{id: 88_421, body: "Morning"}}, %{note: nil}, %{note: nil}] =
             page.days

    assert page.trip_stream == Dawarich.TripStream.stream_name(884_201)

    TripsSeeds.shared_link!(%{
      id: "a8510000-0000-4000-8000-0000000000a3",
      resource_type: 0,
      trip_id: 884_201,
      user_id: 8842
    })

    assert {:ok, %{shared: true}} = TripPage.load(user, 884_201, @now)
    assert {:ok, %{recalculating: true}} = TripPage.load(user, 884_201, DateTime.add(@now, 29))
    assert {:ok, %{recalculating: false}} = TripPage.load(user, 884_201, DateTime.add(@now, 31))
    assert {:ok, %{recalculating: false}} = TripPage.load(user, 884_201, DateTime.add(@now, 3600))
  end

  test "load admits an uncalculated trip as an empty read" do
    TripsSeeds.user!(8843)
    TripsSeeds.trip!(%{id: 884_301, user_id: 8843, path: nil})

    assert {:ok, %{map_state: :empty, has_path: false, path_json: ""}} =
             TripPage.load(Dawarich.Accounts.get(8843), 884_301, @now)
  end
end
