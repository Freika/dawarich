defmodule Dawarich.TripGateTest do
  use ExUnit.Case, async: false

  alias Dawarich.TripList
  alias Dawarich.Test.TripsSeeds

  @path [[12.37, 51.338], [12.381, 51.341]]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    user = TripsSeeds.user!(8801)
    foreign = TripsSeeds.user!(8899)
    TripsSeeds.trip!(%{id: 880_101, user_id: 8801, path: @path})
    %{user: user, foreign: foreign}
  end

  defp trip!(id, attrs \\ %{}),
    do: TripsSeeds.trip!(Map.merge(%{id: id, user_id: 8801, path: @path}, attrs))

  describe "the trip list" do
    test "a page of ordinary trips is Phoenix's; malformed settings or an absurd page are not", %{
      user: user
    } do
      styled = TripsSeeds.user!(8804, %{"maps_maplibre_style" => ["dark"]})
      assert TripList.gate(user, 1) == :phoenix
      assert TripList.gate(user, 2) == :phoenix
      assert TripList.gate(styled, 1) == :rails
      assert TripList.gate(user, 10_000_000_000_000) == :rails
    end

    test "a listed trip with a plan preview, an empty path or odd countries sends only its page to Rails",
         %{user: user} do
      for n <- 1..6,
          do:
            trip!(880_500 + n, %{
              started_at: NaiveDateTime.add(~N[2025-01-01 08:00:00], -n * 86_400)
            })

      trip!(880_510, %{
        path: nil,
        started_at: ~N[2027-01-01 08:00:00],
        ended_at: ~N[2027-01-02 08:00:00]
      })

      TripsSeeds.planned!("planned_days", 880_510)

      assert TripList.gate(user, 1) == :rails
      assert TripList.gate(user, 2) == :phoenix

      TripsSeeds.path!(880_510, @path)
      assert TripList.gate(user, 1) == :phoenix

      TripsSeeds.empty_path!(880_510)
      assert TripList.gate(user, 1) == :rails
    end

    test "countries must be an empty object or an array of strings", %{user: user} do
      trip!(880_601, %{
        visited_countries: %{"Germany" => 1},
        started_at: ~N[2027-02-01 08:00:00],
        ended_at: ~N[2027-02-02 08:00:00]
      })

      assert TripList.gate(user, 1) == :rails
    end

    test "a null inside the countries array sends the page to Rails too", %{foreign: foreign} do
      TripsSeeds.trip!(%{
        id: 880_602,
        user_id: foreign.id,
        path: @path,
        visited_countries: [nil],
        started_at: ~N[2027-02-03 08:00:00],
        ended_at: ~N[2027-02-04 08:00:00]
      })

      assert TripList.gate(foreign, 1) == :rails
    end

    test "a planned_unplanned_places row alone also sends a path-less trip's page to Rails", %{
      user: user
    } do
      trip!(880_701, %{
        path: nil,
        started_at: ~N[2027-03-01 08:00:00],
        ended_at: ~N[2027-03-02 08:00:00]
      })

      TripsSeeds.planned!("planned_unplanned_places", 880_701)

      assert TripList.gate(user, 1) == :rails
    end

    test "a zone PostgreSQL does not list or a timezone that is not a string sends the list to Rails" do
      assert TripList.gate(TripsSeeds.user!(8805, %{"timezone" => "Europe/Atlantis"}), 1) ==
               :rails

      assert TripList.gate(TripsSeeds.user!(8806, %{"timezone" => 5}), 1) == :rails
    end

    test "a friendly, blank or missing zone stays with Phoenix, resolved as Rails resolves it" do
      assert TripList.gate(TripsSeeds.user!(8807, %{"timezone" => "Berlin"}), 1) == :phoenix
      assert TripList.gate(TripsSeeds.user!(8808, %{"timezone" => " "}), 1) == :phoenix
      assert TripList.gate(TripsSeeds.user!(8809, %{}), 1) == :phoenix
    end
  end
end
