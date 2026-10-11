defmodule DawarichWeb.TripPlanHostsTest do
  use Dawarich.IngestCase, async: false
  require Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds, ParityHTML, MapStimulus, NativeTripCorpus}
  import Phoenix.ConnTest
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Trips.WebForm
  alias Dawarich.Jobs.Ownership
  @endpoint DawarichWeb.Endpoint

  @effects File.read!("test/fixtures/trips/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @now ~U[2026-10-03 10:00:00.000000Z]
  @tables ~w(planned_days planned_stops planned_day_notes planned_reservations planned_accommodations planned_travellers planned_unplanned_places)

  defp value(key, raw) do
    cond do
      is_nil(raw) ->
        nil

      key in ~w(latitude longitude) ->
        Decimal.new(raw)

      key in ~w(date starts_on ends_on) ->
        Date.from_iso8601!(raw)

      key in ~w(created_at updated_at starts_at ends_at noted_at source_synced_at) and
          String.contains?(raw, "T") ->
        raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

      true ->
        raw
    end
  end

  defp seed(entry) do
    before = entry["before"]
    actor = before["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-itinerary-#{actor["id"]}@example.invalid",
      api_key: "a8r-k-#{actor["id"]}",
      settings: actor["settings"]
    })

    for source <- before["trip_sources"],
        do:
          Repo.insert_all("trip_sources", [
            Map.merge(Map.new(source, fn {k, v} -> {k, if(k == "status", do: 0, else: v)} end), %{
              "created_at" => DateTime.to_naive(@now),
              "updated_at" => DateTime.to_naive(@now)
            })
          ])

    [trip] = before["trips"]

    TripsSeeds.trip!(%{
      id: trip["id"],
      user_id: actor["id"],
      path: trip["path"],
      name: trip["name"],
      distance: trip["distance"],
      visited_countries: trip["visited_countries"],
      started_at: value("starts_at", trip["started_at"]),
      ended_at: value("ends_at", trip["ended_at"]),
      source_identifier: trip["source_identifier"],
      source_status: if(trip["source_status"] == "stopped", do: 1, else: 0),
      trip_source_id: trip["trip_source_id"],
      source_synced_at: value("source_synced_at", trip["source_synced_at"])
    })

    for table <- @tables do
      rows =
        for row <- before[table], do: Map.new(row, fn {key, raw} -> {key, value(key, raw)} end)

      Repo.insert_all(table, rows)
    end

    for note <- before["notes"] do
      TripsSeeds.note!(%{
        id: note["id"],
        trip_id: trip["id"],
        user_id: actor["id"],
        body: note["body"],
        noted_at: value("noted_at", note["noted_at"])
      })

      Repo.query!("UPDATE notes SET source_digest=$1 WHERE id=$2", [
        note["source_digest"],
        note["id"]
      ])
    end

    for point <- before["points"],
        do:
          TripsSeeds.point!(%{
            id: point["id"],
            user_id: point["user_id"],
            timestamp: point["timestamp"],
            at: point["lonlat"]
          })

    Ownership.put!(Repo, "command:trips.calculate", :oban)
    {Dawarich.Accounts.get(actor["id"]), trip["id"]}
  end

  defp fragment(html, selector),
    do: html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.to_html()

  test "native plan show hosts retain source itinerary and independent managed forms" do
    Repo.query!("DELETE FROM countries")

    for entry <- @effects, String.starts_with?(entry["name"], "plan_") do
      {user, id} = seed(entry)

      selector =
        cond do
          String.ends_with?(entry["name"], "_show") -> "#trip-shell"
          String.ends_with?(entry["name"], "_edit") -> ".mx-auto.my-5"
          true -> "#trips"
        end

      html =
        case selector do
          "#trip-shell" ->
            assert {:ok, page} = Dawarich.TripPage.load(user, id, @now)

            if entry["name"] == "plan_future_stats_show" do
              assert Enum.any?(page.days, &(&1.stats != nil))
              assert page.plan_on_map
            end

            NativeTripCorpus.render(user, id, @now)

          ".mx-auto.my-5" ->
            assert {:ok, form} = WebForm.load(Repo, user, id, %{})

            Phoenix.LiveViewTest.render_component(&DawarichWeb.TripForm.page/1, %{
              form: form,
              locale: "en",
              csrf: "CSRF",
              base_url: "http://www.example.com"
            })

          "#trips" ->
            scope = Dawarich.Maps.principal(user, "en")
            assert {:ok, list} = Dawarich.Maps.Dependencies.Trip.list(scope, 1, 1, now: @now)

            "<div id=trips>" <>
              Enum.map_join(list.entries, fn trip ->
                Phoenix.LiveViewTest.render_component(&DawarichWeb.NativeTripCard.trip_card/1, %{
                  trip: trip,
                  settings: list.settings,
                  locale: "en"
                })
              end) <> "</div>"
        end

      golden = File.read!("test/fixtures/trips/remaining/pages/#{entry["name"]}.html")

      if selector == "#trip-shell" do
        NativeTripCorpus.assert_values(html, golden)

        assert NativeTripCorpus.text(html, "#native-trip-itinerary") ==
                 NativeTripCorpus.text(golden, "section[aria-labelledby=trip-plan-title]")

        assert NativeTripCorpus.attrs(html, "#native-trip-itinerary a", "href") ==
                 NativeTripCorpus.attrs(
                   golden,
                   "section[aria-labelledby=trip-plan-title] a",
                   "href"
                 )

        refute String.contains?(html, "data-controller")
        scope = Dawarich.Maps.principal(user, "en")
        assert {:ok, view} = Dawarich.Maps.Dependencies.Trip.view(scope, id, now: @now)
        assert {:ok, data} = Dawarich.Maps.Dependencies.Trip.read(scope, id, now: @now)

        assert view.presentation.map_state ==
                 if(
                   NativeTripCorpus.attrs(golden, "[data-testid=trip-plan-map]", "data-testid") ==
                     [],
                   do: :path,
                   else: :plan
                 )

        plan =
          NativeTripCorpus.attrs(
            golden,
            "[data-trip-maplibre-plan-value]",
            "data-trip-maplibre-plan-value"
          ) ++
            NativeTripCorpus.attrs(
              golden,
              "[data-trip-maplibre-preview-plan-value]",
              "data-trip-maplibre-preview-plan-value"
            )

        for raw <- plan, do: assert(data["plan"] == Jason.decode!(raw))
      else
        if selector == "#trips" do
          assert NativeTripCorpus.text(html, "#trip-#{id}") ==
                   NativeTripCorpus.text(golden, "#trip-#{id}")

          assert NativeTripCorpus.attrs(html, "[phx-hook=MapPreview]", "data-map-config") !=
                   []

          refute html =~ "data-controller"

          assert {:ok, data} =
                   Dawarich.Maps.Dependencies.Trip.read(Dawarich.Maps.principal(user, "en"), id,
                     now: @now
                   )

          for raw <-
                NativeTripCorpus.attrs(
                  golden,
                  "[data-trip-maplibre-preview-plan-value]",
                  "data-trip-maplibre-preview-plan-value"
                ),
              do: assert(data["plan"] == Jason.decode!(raw))
        else
          actual = ParityHTML.normalize(fragment(html, selector))
          expected = ParityHTML.normalize(fragment(golden, selector))

          assert actual == expected,
                 entry["name"] <> ": " <> ParityHTML.first_difference(actual, expected)

          actual_attrs = MapStimulus.attributes(MapStimulus.prepare(html), [selector])
          expected_attrs = MapStimulus.attributes(MapStimulus.prepare(golden), [selector])

          expected_attrs =
            if selector == ".mx-auto.my-5",
              do: [{selector, "form", [{"data-turbo", "false"}]} | expected_attrs],
              else: expected_attrs

          assert actual_attrs == expected_attrs,
                 entry["name"] <>
                   inspect(
                     Enum.zip(actual_attrs, expected_attrs) |> Enum.find(fn {a, b} -> a != b end),
                     limit: :infinity
                   )
        end
      end

      for field <- ~w(name started_at ended_at), selector == ".mx-auto.my-5" do
        assert LazyHTML.from_document(html)
               |> LazyHTML.query("#trip_#{field}")
               |> LazyHTML.attribute("readonly") ==
                 LazyHTML.from_document(golden)
                 |> LazyHTML.query("#trip_#{field}")
                 |> LazyHTML.attribute("readonly")
      end

      conn = RailsUser.signed_in(user.id) |> get(entry["request"]["path"])
      assert conn.status == 200, entry["name"]

      marker =
        cond do
          selector == "#trip-shell" -> "trip-shell"
          selector == "#trips" -> "native-trip-preview"
          true -> "trip-maplibre-preview"
        end

      assert conn.resp_body =~ marker
    end

    {user, id} = seed(Enum.find(@effects, &(&1["name"] == "managed_update")))

    assert {:ok, row} =
             Dawarich.Trips.WebWrite.run(
               Repo,
               :update,
               user,
               id,
               %{"name" => "Submitted despite readonly"},
               %{now: @now}
             )

    assert row.name == "Submitted despite readonly"

    trip =
      TripsSeeds.trip!(%{
        id: 899_999,
        user_id: user.id,
        path: nil,
        visited_countries: [],
        distance: 0
      })

    assert {:ok, page} = Dawarich.TripPage.load(user, trip, @now)
    refute page.plan_on_map
    assert page.map_state == :empty

    upstream = upstream!()
    previous = Application.get_env(:dawarich, :rails_routes)
    Application.put_env(:dawarich, :rails_routes, ["trips"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, previous) end)
    before = Repo.query!("SELECT count(*) FROM job_outbox").rows

    for path <- ["/trips/#{id}/edit"] do
      {{line, _}, conn} = forwarded(upstream, fn -> RailsUser.signed_in(user.id) |> get(path) end)
      assert conn.status == 204
      assert line =~ "GET #{path} HTTP/1.1"
    end

    index = RailsUser.signed_in(user.id) |> get("/trips")
    assert index.status == 200
    assert index.resp_body =~ "id=\"trips\""
    refute index.resp_body =~ "data-controller"
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == before
    conn = RailsUser.signed_in(user.id) |> get("/trips/#{id}")
    assert conn.status == 200
    assert String.contains?(conn.resp_body, "trip-shell")
    refute String.contains?(conn.resp_body, "data-controller")
    assert commands() == []
  end
end
