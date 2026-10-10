defmodule DawarichWeb.PlaceNavigationTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Test.{FrameSeeds, RailsUser, ParityHTML, MapStimulus}
  @endpoint DawarichWeb.Endpoint
  @effects File.read!("test/fixtures/places/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @responses File.read!("test/fixtures/places/remaining/responses.json")
             |> Jason.decode!()
             |> Map.fetch!("responses")
  @providers ~w(PHOTON_API_HOST GEOAPIFY_API_KEY NOMINATIM_API_HOST LOCATIONIQ_API_KEY)

  defp request(entry, user) do
    conn = RailsUser.signed_in(user.id) |> put_req_header("accept", entry["request"]["accept"])

    conn =
      if entry["request"]["framed"],
        do: put_req_header(conn, "turbo-frame", "place-drawer"),
        else: conn

    get(
      conn,
      entry["request"]["path"] <>
        if(entry["request"]["params"] == %{},
          do: "",
          else: "?" <> URI.encode_query(entry["request"]["params"])
        )
    )
  end

  test "direct links redirect and nearby hands provider calls back" do
    assert Code.ensure_loaded?(DawarichWeb.PlaceNavigation)
    saved = Map.new(@providers, &{&1, System.get_env(&1)})
    for key <- @providers, do: System.delete_env(key)

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    Repo.query!(
      "DELETE FROM instance_settings WHERE key IN ('photon_api_host','geoapify_api_key','nominatim_api_host','locationiq_api_key')"
    )

    upstream = upstream!()

    for entry <- @effects, entry["request"]["method"] == "get" do
      user = FrameSeeds.seed_place_remainder!(entry)
      expected = Enum.find(@responses, &(&1["name"] == entry["name"]))

      if entry["name"] == "nearby_enabled_zero",
        do: System.put_env("PHOTON_API_HOST", "photon.example.invalid")

      conn =
        if (String.starts_with?(entry["name"], "foreign_") and entry["request"]["framed"]) or
             entry["request"]["accept"] == "text/vnd.turbo-stream.html" do
          {{line, _}, conn} = forwarded(upstream, fn -> request(entry, user) end)
          assert conn.status == 204
          assert line =~ "GET #{entry["request"]["path"]} HTTP/1.1"
          nil
        else
          request(entry, user)
        end

      if conn do
        assert conn.status == expected["status"], entry["name"]

        if expected["headers"]["location"],
          do: assert(get_resp_header(conn, "location") == [expected["headers"]["location"]])

        golden = File.read!("test/fixtures/places/remaining/pages/#{entry["name"]}.html")
        actual = ParityHTML.normalize(conn.resp_body)
        expected_body = ParityHTML.normalize(golden)

        assert actual == expected_body,
               entry["name"] <> ParityHTML.first_difference(actual, expected_body)

        assert MapStimulus.attributes(conn.resp_body, ["turbo-frame"]) ==
                 MapStimulus.attributes(golden, ["turbo-frame"]),
               entry["name"]

        if entry["request"]["framed"], do: assert(conn.resp_body =~ "place-drawer")
      end
    end

    actor = @effects |> Enum.filter(&(&1["request"]["method"] == "get")) |> List.last()
    user = Dawarich.Accounts.get(actor["before"]["actor"]["id"])
    System.put_env("PHOTON_API_HOST", "photon.example.invalid")

    before =
      Repo.query!("SELECT (SELECT count(*) FROM places),(SELECT count(*) FROM job_outbox)").rows

    start_supervised!(Dawarich.Geocoding.FakeHttp)

    Dawarich.Geocoding.FakeHttp.stub(
      "http://photon.example.invalid/reverse?distance_sort=true&lang=en&lat=51.34&limit=5&lon=12.37&radius=0.5",
      200,
      Jason.encode!(%{"type" => "FeatureCollection", "features" => []})
    )

    start_supervised!(hd(Dawarich.Redis.child_specs()))
    conn = RailsUser.signed_in(user.id) |> get("/places/nearby?latitude=51.34&longitude=12.37")
    assert conn.status == 200
    assert conn.resp_body =~ "No nearby places found"

    assert Repo.query!("SELECT (SELECT count(*) FROM places),(SELECT count(*) FROM job_outbox)").rows ==
             before

    for {radius, next} <- [{"0.5", "1.0"}, {"1", "1.5"}, {"1.5", nil}] do
      html =
        RailsUser.signed_in(user.id)
        |> get("/places/nearby?latitude=0&longitude=0&radius=#{radius}")
        |> html_response(200)

      urls =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("a[data-turbo-frame='nearby-places']")
        |> LazyHTML.attribute("href")

      assert urls ==
               if(next,
                 do: ["/places/nearby?latitude=0&limit=5&longitude=0&radius=#{next}"],
                 else: []
               )
    end

    assert commands() == []
  end
end
