defmodule Dawarich.Trips.Sync1160IndexTest do
  use Dawarich.IngestCase, async: true
  alias Dawarich.{Accounts, Trips.Pages}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.TripsSeeds
  @now ~U[2026-10-16 10:00:00Z]

  setup do
    id = System.unique_integer([:positive, :monotonic])
    TripsSeeds.user!(id, %{"timezone" => "America/New_York"})
    %{scope: Scope.for_user(Accounts.get(id), "en"), id: id}
  end

  defp trip(scope, name, attrs \\ %{}) do
    id = System.unique_integer([:positive, :monotonic])

    TripsSeeds.trip!(
      Map.merge(
        %{
          id: id,
          user_id: scope.user.id,
          name: name,
          started_at: ~N[2025-12-31 18:00:00],
          ended_at: ~N[2026-01-01 05:00:00]
        },
        attrs
      )
    )
  end

  defp list(scope, params), do: elem(Pages.list(scope, params, @now), 1)
  defp ids(scope, params), do: Enum.map(list(scope, params).entries, & &1.id)

  test "search decodes rich text and treats wildcard backslash and NUL literally", %{scope: s} do
    a = trip(s, "Literal 100%_\\ holiday")
    b = trip(s, "Beach")
    TripsSeeds.rich_text!(b, "<div>Salt &amp; pepper</div>")
    assert ids(s, %{"q" => "%_\\"}) == [a]
    assert ids(s, %{"q" => " Salt &\0 pepper "}) == [b]
    assert ids(s, %{"q" => "<div>"}) == []
    assert String.length(Pages.normalize(%{"q" => String.duplicate("x", 101)}).q) == 100

    assert Pages.normalize(%{"q" => String.duplicate("e\u0301", 101)}).q ==
             String.duplicate("e\u0301", 50)
  end

  test "search covers notes and every itinerary source without duplicate or foreign trips", %{
    scope: s
  } do
    a = trip(s, "Base")
    trip(s, "Unrelated own trip", %{visited_countries: ["France"]})

    for {table, fields} <- [
          {"planned_days", %{date: ~D[2026-01-01], position: 1, title: "Day needle"}},
          {"planned_unplanned_places", %{name: "Place needle", position: 1}},
          {"planned_accommodations", %{name: "Stay needle"}},
          {"planned_reservations", %{title: "Booking needle"}}
        ] do
      Repo.insert_all(table, [
        Map.merge(fields, %{
          trip_id: a,
          created_at: ~N[2026-01-01 00:00:00],
          updated_at: ~N[2026-01-01 00:00:00]
        })
      ])
    end

    [[day]] = Repo.query!("SELECT id FROM planned_days WHERE trip_id=$1", [a]).rows

    Repo.query!(
      "INSERT INTO planned_stops(planned_day_id,name,position,created_at,updated_at) VALUES($1,'Stop needle',1,now(),now())",
      [day]
    )

    TripsSeeds.note!(%{
      id: System.unique_integer([:positive, :monotonic]),
      trip_id: a,
      user_id: s.user.id,
      body: "Note needle",
      noted_at: ~N[2026-01-01 00:00:00]
    })

    other = System.unique_integer([:positive, :monotonic])
    TripsSeeds.user!(other)
    trip(Scope.for_user(Accounts.get(other), "en"), "Foreign needle")

    for q <- [
          "needle",
          "Day needle",
          "Place needle",
          "Stay needle",
          "Booking needle",
          "Stop needle",
          "Note needle"
        ],
        do: assert(ids(s, %{"q" => q}) == [a])
  end

  test "period overlap uses local inclusive start exclusive end and exact country membership", %{
    scope: s
  } do
    a = trip(s, "Boundary")
    trip(s, "Before", %{ended_at: ~N[2026-01-01 04:59:59]})
    trip(s, "After", %{started_at: ~N[2026-02-01 05:00:00], ended_at: ~N[2026-02-02 05:00:00]})
    trip(s, "Punctuation", %{visited_countries: ["Germany, France"]})
    assert ids(s, %{"year" => "2026", "month" => "1", "country" => "Germany"}) == [a]

    assert %{year: nil, month: nil, sort: "newest"} =
             Pages.normalize(%{"year" => "2201", "month" => "1", "sort" => "bad"})

    assert %{month: nil} = Pages.normalize(%{"month" => "1"})
  end

  test "stable sorts pagination and all-trip options survive an empty filtered page", %{scope: s} do
    a = trip(s, "zebra", %{distance: nil})
    b = trip(s, "Alpha", %{distance: 10})
    c = trip(s, "alpha", %{distance: 10})
    assert ids(s, %{"sort" => "oldest"}) == [a, b, c]
    assert ids(s, %{"sort" => "newest"}) == [c, b, a]
    assert ids(s, %{"sort" => "name"}) == [b, c, a]
    assert ids(s, %{"sort" => "distance"}) == [c, b, a]
    result = list(s, %{"q" => "absent", "year" => "2030", "country" => "Atlantis", "page" => "9"})
    assert result.entries == []
    assert result.total_pages == 0
    assert result.options.years == [2026, 2025]
    assert result.options.countries == ["Germany"]
    for n <- 1..7, do: trip(s, "Match #{n}")
    assert length(ids(s, %{"q" => "Match"})) == 6
    assert length(ids(s, %{"q" => "Match", "page" => "2"})) == 1
    assert list(s, %{"q" => "Match", "page" => "99"}).total_pages == 2
  end
end
