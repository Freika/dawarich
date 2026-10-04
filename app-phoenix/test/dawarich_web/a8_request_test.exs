defmodule DawarichWeb.A8RequestTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{A8Request, RailsAuth, RailsCsrf}

  setup do
    actor = RailsUser.insert!(%{id: 8881, email: "a8vv-form@dawarich.test"})
    session = RailsUser.session(actor.id)
    upstream = upstream!()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    %{session: session, token: RailsCsrf.masked_token(session), upstream: upstream}
  end

  defp video_body(token) do
    Plug.Conn.Query.encode(%{
      "authenticity_token" => token,
      "route_video" => %{
        "name" => "Synthetic route",
        "file" => "SYNTHETIC_SIGNED_BLOB",
        "settings" => %{"source" => "trip", "duration_sec" => "15"}
      }
    })
  end

  defp request(ctx, method, path, body, headers \\ []) do
    method
    |> conn(path, body)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/vnd.turbo-stream.html")
    |> put_req_header("origin", "http://www.example.com")
    |> then(fn conn ->
      Enum.reduce(headers, conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)
    end)
    |> RailsAuth.call([])
    |> A8Request.call([])
  end

  defp assert_replay(ctx, method, path, body, headers \\ []) do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    before =
      Repo.query!("SELECT (SELECT count(*) FROM route_videos), (SELECT count(*) FROM visits)").rows

    {{line, received}, conn} =
      forwarded(ctx.upstream, fn -> request(ctx, method, path, body, headers) end)

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})

    assert conn.status == 204
    assert conn.halted
    assert line == "#{method |> Atom.to_string() |> String.upcase()} #{path} HTTP/1.1"
    assert received == body

    assert Repo.query!(
             "SELECT (SELECT count(*) FROM route_videos), (SELECT count(*) FROM visits)"
           ).rows == before

    assert commands() == []
    conn
  end

  test "ordinary video recipe fields decode without changing raw bytes", ctx do
    body = video_body(ctx.token)
    conn = request(ctx, :post, "/route_videos", body)
    refute conn.halted
    assert conn.assigns.current_user.id == 8881

    assert conn.assigns.api_params["route_video"] == %{
             "name" => "Synthetic route",
             "file" => "SYNTHETIC_SIGNED_BLOB",
             "settings" => %{"source" => "trip", "duration_sec" => "15"}
           }

    assert conn.private.dawarich_raw_body == body
    assert conn.assigns.a8_action == :video_create

    parts = [
      {"authenticity_token", ctx.token},
      {"route_video[name]", "Synthetic route"},
      {"route_video[file]", "SYNTHETIC_SIGNED_BLOB"},
      {"route_video[settings][source]", "trip"}
    ]

    multipart =
      Enum.map_join(parts, "", fn {key, value} ->
        "--a8vv\r\nContent-Disposition: form-data; name=\"#{key}\"\r\n\r\n#{value}\r\n"
      end) <> "--a8vv--\r\n"

    conn =
      request(ctx, :post, "/route_videos", multipart, [
        {"content-type", "multipart/form-data; boundary=a8vv"}
      ])

    refute conn.halted
    assert conn.assigns.api_params["route_video"]["settings"] == %{"source" => "trip"}
    assert conn.private.dawarich_raw_body == multipart
  end

  test "pure Turbo Accept is admitted by the plug and unsupported Accept replays", ctx do
    body = video_body(ctx.token)
    conn = request(ctx, :post, "/route_videos", body)
    refute conn.halted
    assert conn.assigns.a8_format == :turbo_stream
    assert_replay(ctx, :post, "/route_videos", body, [{"accept", "application/json"}])
  end

  test "only the action-specific POST method override is normalized", ctx do
    body =
      Plug.Conn.Query.encode(%{
        "authenticity_token" => ctx.token,
        "_method" => "delete"
      })

    conn = request(ctx, :post, "/route_videos/42", body)
    refute conn.halted
    assert conn.method == "POST"
    assert conn.assigns.a8_action == :video_destroy
    assert conn.assigns.a8_method == "DELETE"
    refute Map.has_key?(conn.assigns.api_params, "_method")
    assert conn.private.dawarich_raw_body == body

    for override <- ~w(patch put get bogus) do
      body = Plug.Conn.Query.encode(%{"authenticity_token" => ctx.token, "_method" => override})
      assert_replay(ctx, :post, "/route_videos/42", body)
    end

    settings =
      Plug.Conn.Query.encode(%{
        "authenticity_token" => ctx.token,
        "_method" => "patch",
        "settings" => %{"visit_radius_meters" => "75"}
      })

    conn = request(ctx, :post, "/settings/visits", settings)
    refute conn.halted
    assert conn.assigns.a8_action == :settings_update
    assert conn.assigns.a8_method == "PATCH"

    for {override, action} <- [{"patch", :visit_update}, {"delete", :visit_destroy}] do
      params = %{"authenticity_token" => ctx.token, "_method" => override}

      params =
        if override == "patch", do: Map.put(params, "visit", %{"name" => "Edited"}), else: params

      conn = request(ctx, :post, "/visits/42", Plug.Conn.Query.encode(params))
      refute conn.halted
      assert conn.assigns.a8_action == action
      assert conn.assigns.a8_method == String.upcase(override)
      assert conn.method == "POST"
    end
  end

  test "invalid token or foreign origin replays before writes", ctx do
    assert_replay(ctx, :post, "/route_videos", video_body("invalid"))

    assert_replay(ctx, :post, "/route_videos", video_body(ctx.token), [
      {"origin", "http://foreign.test"}
    ])

    signed_out = %{ctx | session: %{}}
    assert_replay(signed_out, :post, "/route_videos", video_body(ctx.token))
  end

  test "duplicate scalar and scalar-array conflict replays original request", ctx do
    token = "authenticity_token=" <> URI.encode_www_form(ctx.token)

    for raw <- [
          "route_video[name]=first&route_video[name]=second&route_video[file]=BLOB",
          "visit_ids=1&visit_ids[]=2&status=confirmed",
          "route_video[name]=first&route_video[name][]=second&route_video[file]=BLOB"
        ] do
      path =
        if String.starts_with?(raw, "visit_ids"), do: "/visits/bulk_update", else: "/route_videos"

      method = if path == "/visits/bulk_update", do: :patch, else: :post
      assert_replay(ctx, method, path, token <> "&" <> raw)
    end

    body = token <> "&visit_ids[]=1&visit_ids[]=2&status=confirmed"
    conn = request(ctx, :patch, "/visits/bulk_update", body)
    refute conn.halted
    assert conn.assigns.api_params["visit_ids"] == ["1", "2"]
  end
end
