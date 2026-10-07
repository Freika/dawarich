defmodule Dawarich.TripGateTest do
  use ExUnit.Case, async: false

  alias Dawarich.{TripList, TripPage}
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

    test "a listed trip with a plan preview or an empty path stays with Phoenix",
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

      assert TripList.gate(user, 1) == :phoenix
      assert TripList.gate(user, 2) == :phoenix

      TripsSeeds.path!(880_510, @path)
      assert TripList.gate(user, 1) == :phoenix

      TripsSeeds.empty_path!(880_510)
      assert TripList.gate(user, 1) == :phoenix
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

    test "a planned_unplanned_places row alone keeps a path-less trip's page in Phoenix", %{
      user: user
    } do
      trip!(880_701, %{
        path: nil,
        started_at: ~N[2027-03-01 08:00:00],
        ended_at: ~N[2027-03-02 08:00:00]
      })

      TripsSeeds.planned!("planned_unplanned_places", 880_701)

      assert TripList.gate(user, 1) == :phoenix
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

  describe "the trip page" do
    test "a calculated trip of a user without photo integrations is Phoenix's", %{user: user} do
      assert {:ok,
              %{settings: %{unit: "km"}, zone: "Europe/Berlin", span: %{near_transition: false}}} =
               TripPage.gate(user, 880_101)
    end

    test "a missing or foreign trip goes to Rails, which answers 404", %{
      user: user,
      foreign: foreign
    } do
      assert TripPage.gate(user, 880_199) == :rails
      assert TripPage.gate(foreign, 880_101) == :rails
    end

    test "uncalculated trips admit rendering while malformed countries stay on Rails",
         %{user: user} do
      for {id, attrs} <- [
            {880_102, %{path: nil}},
            {880_103, %{distance: nil}},
            {880_104, %{visited_countries: []}},
            {880_105, %{visited_countries: %{}}}
          ] do
        trip!(id, attrs)
        assert {:ok, _} = TripPage.gate(user, id), inspect(attrs)
      end

      trip!(880_106, %{visited_countries: ["Germany", 7]})
      assert TripPage.gate(user, 880_106) == :rails

      trip!(880_107, %{path: nil})
      TripsSeeds.empty_path!(880_107)
      assert {:ok, _} = TripPage.gate(user, 880_107)
    end

    test "TREK reads stay native while unsupported descriptions and dates stay on Rails",
         %{user: user} do
      ~w(planned_days planned_reservations planned_accommodations planned_travellers planned_unplanned_places)
      |> Enum.with_index(880_110)
      |> Enum.each(fn {table, id} ->
        trip!(id)
        TripsSeeds.planned!(table, id)
        assert {:ok, _} = TripPage.gate(user, id), table
      end)

      trip!(880_120, %{source_identifier: "12"})
      TripsSeeds.trip_source!(88_101, 8801)
      trip!(880_121, %{trip_source_id: 88_101})
      trip!(880_122)
      TripsSeeds.rich_text!(880_122, "<div>Along the Elster</div>")
      trip!(880_123)
      TripsSeeds.rich_text!(880_123, "   ")
      trip!(880_124, %{ended_at: ~N[2038-01-19 03:14:08]})
      trip!(880_127)

      TripsSeeds.rich_text!(
        880_127,
        ~s(<action-text-attachment content-type="text/html" content="&lt;div&gt;source render error&lt;/div&gt;"></action-text-attachment>)
      )

      assert {:ok, _} = TripPage.gate(user, 880_120)
      assert {:ok, _} = TripPage.gate(user, 880_121)
      assert {:ok, %{description: "<div>Along the Elster</div>"}} = TripPage.gate(user, 880_122)
      assert {:ok, %{description: nil}} = TripPage.gate(user, 880_123)
      assert TripPage.gate(user, 880_124) == :rails
      assert TripPage.gate(user, 880_127) == :rails
    end

    test "timestamps below int4 go to Rails while its exact lower boundary is admitted", %{
      user: user
    } do
      trip!(880_125, %{started_at: ~N[1901-12-13 20:45:51], ended_at: ~N[1901-12-13 21:45:52]})
      trip!(880_126, %{started_at: ~N[1901-12-13 20:45:52], ended_at: ~N[1901-12-13 21:45:52]})

      assert TripPage.gate(user, 880_125) == :rails
      assert TripPage.load(user, 880_125, ~U[2026-05-15 12:00:00Z]) == :rails
      assert {:ok, _} = TripPage.gate(user, 880_126)
    end

    test "photo integrations and settings Rails would raise on go to Rails" do
      photos =
        TripsSeeds.user!(8802, %{
          "immich_url" => "https://immich.example",
          "immich_api_key" => "fixture"
        })

      leagues = TripsSeeds.user!(8803, %{"maps" => %{"distance_unit" => "leagues"}})
      TripsSeeds.trip!(%{id: 880_201, user_id: 8802, path: @path})
      TripsSeeds.trip!(%{id: 880_301, user_id: 8803, path: @path})

      assert {:ok, _} = TripPage.gate(photos, 880_201)
      assert TripPage.gate(leagues, 880_301) == :rails
    end

    test "a zone PostgreSQL does not list or a timezone that is not a string sends the page to Rails" do
      for {user_id, trip_id, settings} <- [
            {8805, 880_701, %{"timezone" => "Europe/Atlantis"}},
            {8806, 880_702, %{"timezone" => 5}}
          ] do
        user = TripsSeeds.user!(user_id, settings)
        TripsSeeds.trip!(%{id: trip_id, user_id: user_id, path: @path})
        assert TripPage.gate(user, trip_id) == :rails, inspect(settings)
      end
    end

    test "a duration that borrows a previous-month wall time within a day of an offset change goes to Rails",
         %{user: user} do
      trip!(880_401, %{started_at: ~N[2026-03-30 08:00:00], ended_at: ~N[2026-04-29 00:30:00]})
      trip!(880_402, %{started_at: ~N[2026-10-28 08:00:00], ended_at: ~N[2026-11-25 01:30:00]})
      trip!(880_403, %{started_at: ~N[2026-03-20 09:00:00], ended_at: ~N[2026-04-10 07:00:00]})

      assert TripPage.gate(user, 880_401) == :rails
      assert TripPage.gate(user, 880_402) == :rails
      assert {:ok, _} = TripPage.gate(user, 880_403)
    end
  end
end
