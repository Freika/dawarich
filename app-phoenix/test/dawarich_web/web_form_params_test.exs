defmodule DawarichWeb.WebFormParamsTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{A8Request, RailsAuth, RailsCsrf, WebFormParams}

  setup do
    actor = RailsUser.insert!(%{id: 9181, email: "a6s4-form@example.invalid"})
    session = RailsUser.session(actor.id)
    upstream = upstream!()
    %{session: session, token: RailsCsrf.masked_token(session), upstream: upstream}
  end

  defp request(ctx, body, headers \\ []) do
    conn(:post, "/route_videos", body)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
    |> put_req_header("origin", "http://www.example.com")
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)
    end)
    |> RailsAuth.call([])
    |> A8Request.call([])
  end

  test "extraction preserves A8 decoding and raw replay bytes", ctx do
    body =
      "authenticity_token=" <>
        URI.encode_www_form(ctx.token) <>
        "&route_video[name]=Caf%C3%A9+%26+tea&route_video[file]=BLOB&route_video[settings][source]=trip"

    result =
      conn(:post, "/route_videos", body)
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> WebFormParams.params(repeated: ["visit_ids[]"])

    assert elem(result, 0) == :ok
    {:ok, parsed, params} = result

    assert parsed.private.dawarich_raw_body == body
    assert params["route_video"]["name"] == "Café & tea"

    conn = request(ctx, body)
    refute conn.halted
    assert conn.private.dawarich_raw_body == body

    assert conn.assigns.api_params["route_video"] == %{
             "name" => "Café & tea",
             "file" => "BLOB",
             "settings" => %{"source" => "trip"}
           }

    parts = [
      {"authenticity_token", ctx.token},
      {"route_video[name]", "Café & tea"},
      {"route_video[file]", "BLOB"},
      {"route_video[settings][source]", "trip"}
    ]

    multipart =
      Enum.map_join(parts, "", fn {key, value} ->
        "--a6s4\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
      end) <> "--a6s4--\r\n"

    conn = request(ctx, multipart, [{"content-type", "multipart/form-data; boundary=a6s4"}])
    refute conn.halted
    assert conn.private.dawarich_raw_body == multipart
    assert conn.assigns.api_params["route_video"]["name"] == "Café & tea"
  end

  test "duplicate scalars nested conflicts stay rejected before A8 mutation", ctx do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})
    token = "authenticity_token=" <> URI.encode_www_form(ctx.token)

    for suffix <- [
          "route_video[name]=first&route_video[name]=second&route_video[file]=BLOB",
          "route_video=scalar&route_video[name]=second&route_video[file]=BLOB",
          "route_video[name]=first&route_video[name][]=second&route_video[file]=BLOB",
          "route_video[name]=%FF&route_video[file]=BLOB",
          "route_video[name]=%xy&route_video[file]=BLOB",
          "point_ids[]=1&point_ids[]=2"
        ] do
      body = token <> "&" <> suffix

      result =
        conn(:post, "/route_videos", body)
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))
        |> WebFormParams.params(repeated: ["visit_ids[]"])

      assert elem(result, 0) == :replay

      {{line, raw}, conn} = forwarded(ctx.upstream, fn -> request(ctx, body) end)
      assert line == "POST /route_videos HTTP/1.1"
      assert raw == body
      assert conn.status == 204
      assert conn.halted
    end

    assert commands() == []
    assert Repo.query!("SELECT count(*) FROM route_videos").rows == [[0]]
  end
end
