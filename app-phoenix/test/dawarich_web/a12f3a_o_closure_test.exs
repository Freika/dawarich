defmodule DawarichWeb.A12f3aOClosureTest do
  use Dawarich.IngestCase, async: false

  import Plug.Conn
  import Plug.Test
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{A8Gate, A8Request, ImportsRequest, MapWriteRequest, RailsAuth, RailsCsrf}

  setup do
    actor = RailsUser.insert!(%{id: 8891, email: "o02-dispatch@example.test"})
    session = RailsUser.session(actor.id)
    upstream = upstream!()
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    %{session: session, token: RailsCsrf.masked_token(session), upstream: upstream}
  end

  @tag a12f3a_o02: true
  test "O02: domain dispatch preserves original body and has no cross-domain admission effect",
       ctx do
    before = effects()

    a8 = [
      {:post, "/trips", %{"trip" => %{"name" => "Leipzig"}}, :trip_create,
       DawarichWeb.TripRequest, DawarichWeb.TripRequestGate},
      {:post, "/trips/42/notes", %{"note" => %{"body" => "<p>Synthetic</p>"}}, :note_create,
       DawarichWeb.TripRequest, DawarichWeb.TripRequestGate},
      {:post, "/places", %{"place" => %{"name" => "Leipzig", "tag_ids" => ["1", "2"]}},
       :place_create, DawarichWeb.PlaceRequest, DawarichWeb.PlaceRequestGate},
      {:patch, "/visits/42", %{"visit" => %{"name" => "Leipzig"}}, :visit_update,
       DawarichWeb.VisitRequest, DawarichWeb.VisitRequestGate},
      {:patch, "/settings/visits", %{"settings" => %{"visit_radius_meters" => "75"}},
       :settings_update, DawarichWeb.VisitRequest, DawarichWeb.VisitRequestGate},
      {:post, "/route_videos",
       %{"route_video" => %{"name" => "Synthetic", "file" => "SYNTHETIC_BLOB"}}, :video_create,
       DawarichWeb.RouteVideoRequest, DawarichWeb.RouteVideoRequestGate}
    ]

    for {method, path, attrs, action, domain, gate} <- a8 do
      body = encode(attrs, ctx.token)
      conn = request(ctx, method, path, body)
      assert apply(A8Request, :request_module, [conn]) == domain
      assert apply(domain, :fields?, [action, Map.put(attrs, "authenticity_token", ctx.token)])
      assert apply(gate, :actions?, [conn, %{}])
      assert A8Gate.actions?(conn, %{})
      admitted = A8Request.call(conn, [])
      refute admitted.halted
      assert admitted.assigns.a8_action == action
      assert admitted.assigns.api_params == Map.put(attrs, "authenticity_token", ctx.token)
      assert admitted.private.dawarich_raw_body == body
      assert effects() == before

      System.put_env("SELF_HOSTED", "false")
      refute apply(gate, :actions?, [conn, %{}])
      refute A8Gate.actions?(conn, %{})
      System.put_env("SELF_HOSTED", "true")

      for rejected <- [
            encode(attrs, "invalid"),
            encode(Map.put(attrs, "foreign_domain", "x"), ctx.token)
          ] do
        replay(ctx, method, path, rejected, A8Request)
        assert effects() == before
      end
    end

    for {method, path, attrs, action, domain, accept} <- [
          {:post, "/tags", %{"tag" => %{"name" => "Synthetic"}}, :tag_create,
           DawarichWeb.MapTagRequest, "text/html"},
          {:delete, "/points/bulk_destroy", %{"point_ids" => ["1", "2"]}, :point_destroy,
           DawarichWeb.MapPointRequest, "text/html"},
          {:patch, "/tracks/41/segments/42",
           %{"track_segment" => %{"transportation_mode" => "walking"}}, :segment_update,
           DawarichWeb.MapSegmentRequest, "text/vnd.turbo-stream.html"}
        ] do
      body = encode(attrs, ctx.token)
      conn = request(ctx, method, path, body, accept)
      assert apply(MapWriteRequest, :request_module, [conn]) == domain
      assert apply(domain, :fields?, [action, Map.put(attrs, "authenticity_token", ctx.token)])
      admitted = MapWriteRequest.call(conn, [])
      refute admitted.halted
      assert admitted.assigns.map_write_action == action
      assert admitted.private.dawarich_raw_body == body
      assert admitted.assigns.api_params == Map.put(attrs, "authenticity_token", ctx.token)
      replay(ctx, method, path, encode(attrs, "invalid"), MapWriteRequest, accept)

      replay(
        ctx,
        method,
        path,
        encode(Map.put(attrs, "foreign_domain", "x"), ctx.token),
        MapWriteRequest,
        accept
      )

      assert effects() == before
    end

    area = request(ctx, :post, "/areas", encode(%{"area" => %{"name" => "Synthetic"}}, ctx.token))
    assert apply(MapWriteRequest, :request_module, [area]) == DawarichWeb.AreaRequest
    assert apply(DawarichWeb.AreaRequest, :target, [area.path_info]) == nil

    replay(
      ctx,
      :post,
      "/areas",
      encode(%{"area" => %{"name" => "Synthetic"}}, ctx.token),
      MapWriteRequest
    )

    for {method, path, attrs, form} <- [
          {:post, "/imports", %{"import" => %{"files" => ["SYNTHETIC_BLOB"]}},
           DawarichWeb.Imports.UploadForm},
          {:patch, "/imports/42", %{"import" => %{"name" => "Synthetic"}},
           DawarichWeb.Imports.UpdateForm}
        ] do
      body = encode(attrs, ctx.token)
      conn = request(ctx, method, path, body, "text/html")
      assert apply(ImportsRequest, :request_module, [conn]) == form
      admitted = ImportsRequest.call(conn, [])
      refute admitted.halted
      assert admitted.private.dawarich_raw_body == body
      assert admitted.assigns.api_params == Map.put(attrs, "authenticity_token", ctx.token)
      replay(ctx, method, path, encode(attrs, "invalid"), ImportsRequest, "text/html")

      replay(
        ctx,
        method,
        path,
        encode(Map.put(attrs, "foreign_domain", "x"), ctx.token),
        ImportsRequest,
        "text/html"
      )

      assert effects() == before
    end

    replay(
      ctx,
      :post,
      "/route_videos",
      "route_video[name]=first&route_video[name]=second",
      A8Request
    )

    assert effects() == before
  end

  defp effects do
    Repo.query!("""
    SELECT (SELECT count(*) FROM trips), (SELECT count(*) FROM places),
      (SELECT count(*) FROM visits), (SELECT count(*) FROM route_videos),
      (SELECT count(*) FROM imports), (SELECT count(*) FROM points),
      (SELECT count(*) FROM tags), (SELECT count(*) FROM job_outbox)
    """).rows
    |> then(&{&1, commands()})
  end

  defp encode(attrs, token),
    do: Plug.Conn.Query.encode(Map.put(attrs, "authenticity_token", token))

  defp request(ctx, method, path, body, accept \\ "text/vnd.turbo-stream.html") do
    method
    |> conn(path, body)
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", accept)
    |> put_req_header("origin", "http://www.example.com")
    |> RailsAuth.call([])
  end

  defp replay(ctx, method, path, body, plug, accept \\ "text/vnd.turbo-stream.html") do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    {{line, received}, response} =
      forwarded(ctx.upstream, fn -> plug.call(request(ctx, method, path, body, accept), []) end)

    assert response.status == 204
    assert response.halted
    assert line == "#{method |> Atom.to_string() |> String.upcase()} #{path} HTTP/1.1"
    assert received == body
  end
end
