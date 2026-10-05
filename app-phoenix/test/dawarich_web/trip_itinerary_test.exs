defmodule DawarichWeb.TripItineraryTest do
  use Dawarich.IngestCase, async: false
  require Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds, ParityHTML, MapStimulus}
  alias Dawarich.Trips.PlanRead

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
      api_key: "a8-plan",
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
      path: nil,
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

    {:ok, plan} = PlanRead.load(Repo, actor["id"], trip["id"])
    {plan, actor["settings"], trip["id"]}
  end

  test "itinerary matches Rails and suppresses only unchanged synced note" do
    for entry <- @effects,
        String.starts_with?(entry["name"], "plan_") and String.ends_with?(entry["name"], "_show") do
      {plan, settings, id} = seed(entry)
      plan = DawarichWeb.TripPlanItems.prepare(plan, settings)
      notes = Dawarich.TripPage.day_notes(id)
      golden = File.read!("test/fixtures/trips/remaining/pages/#{entry["name"]}.html")
      on_map = String.contains?(golden, "data-trip-plan-focus-longitude-param")

      html =
        Phoenix.LiveViewTest.render_component(&DawarichWeb.TripItinerary.itinerary/1, %{
          plan: plan,
          notes: notes,
          plan_on_map: on_map,
          locale: "en",
          now: @now
        })

      rails = ParityHTML.fragment(golden, "section[aria-labelledby='trip-plan-title']")

      assert ParityHTML.normalize(html) == rails,
             entry["name"] <>
               ": " <> ParityHTML.first_difference(ParityHTML.normalize(html), rails)

      actual_attributes =
        MapStimulus.attributes(html, ["section[aria-labelledby='trip-plan-title']"])

      expected_attributes =
        MapStimulus.attributes(golden, ["section[aria-labelledby='trip-plan-title']"])

      assert actual_attributes == expected_attributes,
             inspect({actual_attributes, expected_attributes}, limit: :infinity)

      if entry["name"] == "plan_edited_show", do: assert(html =~ "Source detail")
      if entry["name"] == "plan_synced_show", do: refute(html =~ "Source detail")
    end

    assert commands() == []
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
  end
end
