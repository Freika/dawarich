defmodule DawarichWeb.TripNoteActionsTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  require Phoenix.LiveViewTest
  alias Dawarich.Test.{RailsUser, TripsSeeds, ParityHTML}
  alias DawarichWeb.{TripDaysList, RailsCsrf}

  @effects File.read!("test/fixtures/trips/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses File.read!("test/fixtures/trips/remaining/responses.json")
             |> Jason.decode!()
             |> Map.fetch!("responses")

  defp seed(entry) do
    actor = entry["before"]["actor"]

    RailsUser.insert!(%{
      id: actor["id"],
      email: "a8-noteaction-#{actor["id"]}@example.invalid",
      settings: actor["settings"]
    })

    for trip <- entry["before"]["trips"] do
      if trip["user_id"] != actor["id"],
        do:
          RailsUser.insert!(%{
            id: trip["user_id"],
            email: "other-noteaction-#{trip["user_id"]}@example.invalid"
          })

      TripsSeeds.trip!(%{
        id: trip["id"],
        user_id: trip["user_id"],
        name: trip["name"],
        started_at: naive(trip["started_at"]),
        ended_at: naive(trip["ended_at"])
      })
    end

    for note <- entry["before"]["notes"],
        do:
          Repo.query!(
            "INSERT INTO notes SELECT * FROM json_populate_record(NULL::notes,$1::text::json)",
            [Jason.encode!(note)]
          )

    if entry["before"]["notes"] == [] and entry["after"]["notes"] != [] do
      Repo.query!("SELECT setval(pg_get_serial_sequence('notes','id'),$1,false)", [
        hd(entry["after"]["notes"])["id"]
      ])
    end

    RailsUser.session(actor["id"])
  end

  defp naive(raw), do: raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp textareas(html) do
    for [_, raw] <- Regex.scan(~r/<textarea\b[^>]*>(.*?)<\/textarea>/s, html) do
      value =
        LazyHTML.from_fragment("<textarea>" <> raw <> "</textarea>")
        |> LazyHTML.query("textarea")
        |> LazyHTML.to_tree()
        |> hd()
        |> elem(2)
        |> Enum.join()

      %{"raw" => raw, "value" => value}
    end
  end

  test "note responses replace exact frame and match Rails textarea values" do
    assert Code.ensure_loaded?(DawarichWeb.TripNoteActions)
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)

    for entry <- Enum.sort_by(@effects, &(&1["name"] != "note_create_lf_stream")),
        entry["request"]["method"] in ~w(POST PATCH DELETE),
        String.starts_with?(entry["name"], "note_") or
          entry["name"] in ~w(foreign_note_update foreign_note_destroy) do
      session = seed(entry)
      req = entry["request"]
      params = Map.put(req["params"], "authenticity_token", RailsCsrf.masked_token(session))

      params =
        if req["method"] == "POST",
          do: params,
          else: Map.put(params, "_method", String.downcase(req["method"]))

      conn =
        post_form(
          session,
          Plug.Conn.Query.encode(params),
          [{"accept", req["accept"]}],
          req["path"]
        )

      expected = Enum.find(@responses, &(&1["name"] == entry["name"]))
      assert conn.status == expected["status"], entry["name"]

      if conn.status == 302 do
        assert get_resp_header(conn, "location") == [expected["location"]]

        if expected["flash"] == %{} do
          refute Map.has_key?(conn.resp_cookies, "_dawarich_session")
        else
          assert rails_session(conn)["flash"]["flashes"] == expected["flash"]
        end
      else
        golden = File.read!("test/fixtures/trips/remaining/pages/#{entry["name"]}.html")
        assert ParityHTML.normalize(conn.resp_body) == ParityHTML.normalize(golden), entry["name"]
        assert ParityHTML.stimulus(conn.resp_body) == ParityHTML.stimulus(golden)

        assert Enum.map(textareas(conn.resp_body), & &1["value"]) ==
                 Enum.map(expected["textareas"], & &1["value"])

        assert textareas(conn.resp_body) == expected["textareas"], entry["name"]

        targets =
          conn.resp_body
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("turbo-stream")
          |> LazyHTML.attribute("target")

        assert targets == Enum.map(expected["streams"], & &1["target"])
      end

      if entry["after"]["notes"] != [] and not String.starts_with?(entry["name"], "foreign_") do
        note = hd(entry["after"]["notes"])

        assert Repo.query!("SELECT body FROM notes WHERE id=$1", [note["id"]]).rows == [
                 [note["body"]]
               ]
      end
    end

    for entry <- @effects, String.starts_with?(entry["name"], "note_document_") do
      seed(entry)
      [note] = entry["before"]["notes"]

      html =
        Phoenix.LiveViewTest.render_component(&TripDaysList.note/1, %{
          note: %{id: note["id"], date: ~D[2026-10-03], body: note["body"]},
          trip_id: note["attachable_id"],
          locale: "en",
          rails_csrf_token: "CSRF"
        })

      golden =
        File.read!("test/fixtures/trips/remaining/pages/#{entry["name"]}.html")
        |> LazyHTML.from_document()
        |> LazyHTML.query("#note-#{note["attachable_id"]}-2026-10-03")
        |> LazyHTML.to_html()

      assert ParityHTML.normalize(html) == ParityHTML.normalize(golden)
      expected = Enum.find(@responses, &(&1["name"] == entry["name"]))
      assert textareas(html) == Enum.take(expected["textareas"], 1)

      assert Repo.query!("SELECT body FROM notes WHERE id=$1", [note["id"]]).rows == [
               [note["body"]]
             ]
    end
  end
end
