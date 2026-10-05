defmodule DawarichWeb.PlaceActionsTest do
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
  @now ~U[2026-10-02 10:00:00.000000Z]

  defp request(entry, session) do
    req = entry["request"]

    params =
      Map.put(req["params"], "authenticity_token", DawarichWeb.RailsCsrf.masked_token(session))

    params =
      if req["method"] == "post", do: params, else: Map.put(params, "_method", req["method"])

    raw =
      Enum.reduce(req["params"]["place"] || %{}, Plug.Conn.Query.encode(params), fn {key, value},
                                                                                    raw ->
        if value == nil,
          do: String.replace(raw, "place[#{key}]" <> "=", "place[#{key}]"),
          else: raw
      end)

    headers =
      [{"accept", req["accept"]}] ++
        if(req["framed"], do: [{"turbo-frame", "place-drawer"}], else: [])

    conn =
      Enum.reduce(headers, build_conn(), fn {k, v}, c -> put_req_header(c, k, v) end)
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> assign(:now, @now)

    {fn -> dispatch(conn, @endpoint, :post, req["path"], raw) end, raw}
  end

  test "place responses match drawer modal and list requests" do
    assert Code.ensure_loaded?(DawarichWeb.PlaceActions)
    upstream = upstream!()

    for entry <- @effects, entry["request"]["method"] in ~w(post patch delete) do
      user = FrameSeeds.seed_place_remainder!(entry)
      expected = Enum.find(@responses, &(&1["name"] == entry["name"]))
      {run, raw} = request(entry, RailsUser.session(user.id))
      attrs = entry["request"]["params"]["place"] || %{}

      retained =
        (entry["request"]["method"] == "post" and entry["request"]["accept"] == "text/html") or
          expected["error"] != nil or Enum.any?(attrs, fn {_, v} -> v == nil end)

      conn =
        if retained do
          id = hd(entry["before"]["places"])["id"]

          before =
            Repo.query!(
              "SELECT to_jsonb(p) FROM places p WHERE id >= $1 AND id < $1+20 ORDER BY id",
              [id]
            ).rows

          {{line, received}, conn} = forwarded(upstream, run)
          assert conn.status == 204, entry["name"]
          assert line =~ "POST #{entry["request"]["path"]} HTTP/1.1"
          assert received == raw

          assert Repo.query!(
                   "SELECT to_jsonb(p) FROM places p WHERE id >= $1 AND id < $1+20 ORDER BY id",
                   [id]
                 ).rows == before

          nil
        else
          run.()
        end

      if conn do
        assert conn.status == expected["status"], entry["name"]

        for {key, value} <- expected["headers"],
            do:
              assert(
                get_resp_header(conn, key) == [value],
                entry["name"] <> key <> inspect({get_resp_header(conn, key), value})
              )

        golden = File.read!("test/fixtures/places/remaining/pages/#{entry["name"]}.html")
        actual = ParityHTML.normalize(conn.resp_body)
        expected_body = ParityHTML.normalize(golden)

        assert actual == expected_body,
               entry["name"] <> ": " <> ParityHTML.first_difference(actual, expected_body)

        assert MapStimulus.attributes(conn.resp_body, ["turbo-stream"]) ==
                 MapStimulus.attributes(golden, ["turbo-stream"]),
               entry["name"]

        assert stream_targets(conn.resp_body) == expected["streams"], entry["name"]
        assert data(conn.resp_body) == data(golden), entry["name"]

        if expected["flash"] != %{},
          do: assert(rails_session(conn)["flash"]["flashes"] == expected["flash"])
      end
    end

    assert commands() == []
  end

  defp stream_targets(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("turbo-stream")
      |> LazyHTML.to_tree()
      |> Enum.map(fn {_, attrs, _} ->
        %{
          "action" => List.keyfind(attrs, "action", 0) |> elem(1),
          "target" => List.keyfind(attrs, "target", 0) |> elem(1)
        }
      end)

  defp data(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#place-creation-data")
      |> LazyHTML.attribute("data-place")
      |> Enum.map(&Jason.decode!/1)
end
