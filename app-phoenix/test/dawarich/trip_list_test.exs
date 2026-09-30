defmodule Dawarich.TripListTest do
  use ExUnit.Case, async: false

  alias Dawarich.TripList
  alias Dawarich.Test.TripsSeeds

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    TripsSeeds.user!(8851)
    TripsSeeds.user!(8899)
    %{user: Dawarich.Accounts.get(8851)}
  end

  test "an entry carries the card's values: Oj's path JSON, local dates, Rails' day count", %{
    user: user
  } do
    TripsSeeds.trip!(%{
      id: 885_101,
      user_id: 8851,
      path: [[12.5, 51.25], [12.373468123456789, 51.34]],
      started_at: ~N[2026-05-09 22:30:00],
      ended_at: ~N[2026-05-10 22:30:00.000001]
    })

    TripsSeeds.trip!(%{id: 889_901, user_id: 8899, started_at: ~N[2026-05-09 22:30:00]})

    assert {:ok, %{entries: [entry], total_pages: 1, settings: %{unit: "km"}}} =
             TripList.load(user, 1)

    assert entry == %{
             id: 885_101,
             name: "trip 885101",
             distance: 1000,
             countries: 1,
             path_json: ~S([[12.5,51.25],[12.37346812345679,51.34]]),
             started_on: ~D[2026-05-10],
             ended_on: ~D[2026-05-11],
             day_count: 2
           }
  end

  test "Kaminari's pages of six, newest first; out of range is empty", %{user: user} do
    for n <- 1..7,
        do:
          TripsSeeds.trip!(%{
            id: 885_200 + n,
            user_id: 8851,
            started_at: NaiveDateTime.add(~N[2025-01-01 08:00:00], n * 86_400)
          })

    assert {:ok, %{entries: first, total_pages: 2}} = TripList.load(user, 1)
    assert Enum.map(first, & &1.id) == [885_207, 885_206, 885_205, 885_204, 885_203, 885_202]
    assert {:ok, %{entries: [%{id: 885_201}]}} = TripList.load(user, 2)
    assert {:ok, %{entries: [], total_pages: 0}} = TripList.load(user, 3)
  end

  test "the page agrees with the gate", %{user: user} do
    TripsSeeds.trip!(%{id: 885_301, user_id: 8851, path: nil})
    TripsSeeds.planned!("planned_accommodations", 885_301)
    assert TripList.load(user, 1) == :rails
    assert TripList.gate(user, 1) == :rails
  end

  test "a page past the guard is Rails', same as Kaminari's own out-of-range page", %{
    user: user
  } do
    assert TripList.load(user, 1_000_000_000_001) == :rails
  end

  test "load/2 rejects a timezone Rails would reject, same as the gate" do
    bad = TripsSeeds.user!(8852, %{"timezone" => "Europe/Atlantis"})
    TripsSeeds.trip!(%{id: 885_401, user_id: 8852})
    assert TripList.load(bad, 1) == :rails
  end
end
