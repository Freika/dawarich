defmodule DawarichWeb.TripPlanHostsTest do
  use Dawarich.IngestCase, async: false
  require Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds, ParityHTML, MapStimulus}
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

  test "plan hosts choose map preview and managed form like Rails" do
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

            Phoenix.LiveViewTest.render_component(&DawarichWeb.TripsLive.Show.render/1, %{
              page: page,
              locale: "en",
              rails_csrf_token: "CSRF",
              base_url: "http://www.example.com"
            })

          ".mx-auto.my-5" ->
            assert {:ok, form} = WebForm.load(Repo, user, id, %{})

            Phoenix.LiveViewTest.render_component(&DawarichWeb.TripForm.page/1, %{
              form: form,
              locale: "en",
              csrf: "CSRF",
              base_url: "http://www.example.com"
            })

          "#trips" ->
            assert {:ok, list} = Dawarich.TripList.load(user, 1)

            Phoenix.LiveViewTest.render_component(
              &DawarichWeb.TripsLive.Index.render/1,
              Map.merge(list, %{
                locale: "en",
                page: 1,
                query: %{},
                family_entries: [],
                family_total_pages: 0,
                family_page: 1
              })
            )
        end

      golden = File.read!("test/fixtures/trips/remaining/pages/#{entry["name"]}.html")
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

      assert conn.resp_body =~
               if(selector == "#trip-shell", do: "trip-shell", else: "trip-maplibre-preview")
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

    for path <- ["/trips", "/trips/#{id}", "/trips/#{id}/edit"] do
      {{line, _}, conn} = forwarded(upstream, fn -> RailsUser.signed_in(user.id) |> get(path) end)
      assert conn.status == 204
      assert line =~ "GET #{path} HTTP/1.1"
    end

    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == before
    assert commands() == []
  end
end
