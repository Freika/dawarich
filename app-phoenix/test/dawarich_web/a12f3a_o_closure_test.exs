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

      if domain == DawarichWeb.VisitRequest or gate == DawarichWeb.TripRequestGate do
        assert apply(gate, :actions?, [conn, %{}])
        assert A8Gate.actions?(conn, %{})
      else
        refute apply(gate, :actions?, [conn, %{}])
        refute A8Gate.actions?(conn, %{})
      end

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

    assert apply(DawarichWeb.AreaRequest, :target, [area.path_info]) ==
             {:area_create, ["POST"], ["POST"]}

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

  @tag a12f3a_o02_cloud: true
  test "O02: the domain gate decides Cloud admission while shared envelope guards remain", ctx do
    System.put_env("SELF_HOSTED", "false")
    body = encode(%{"trip" => %{"name" => "Leipzig"}}, ctx.token)
    conn = request(ctx, :post, "/trips", body)
    gate = A8Gate.request_gate(conn)
    assert gate.actions?(conn, %{})
    assert A8Gate.actions?(conn, %{})

    for rejected <- [
          put_req_header(conn, "x-dawarich-client", "unsupported"),
          put_req_header(conn, "x-http-method-override", "DELETE"),
          put_req_header(conn, "content-type", "application/json"),
          %{conn | path_info: ["trips", "42.json"]}
        ] do
      assert gate.actions?(rejected, %{})
      refute A8Gate.actions?(rejected, %{})
    end

    rejected = %{conn | query_string: "foreign_domain=x"}
    refute gate.actions?(rejected, %{})
    refute A8Gate.actions?(rejected, %{})

    {^gate, binary, filename} = :code.get_object_code(gate)
    source = Path.expand("../../lib/dawarich_web/trip_request_gate.ex", __DIR__)

    cloud_policy =
      source |> File.read!() |> String.replace("do: query?(conn)", "do: query?(conn) and false")

    options = Code.compiler_options(ignore_module_conflict: true)

    try do
      Code.compile_string(cloud_policy, source)
      refute gate.actions?(conn, %{})
      refute A8Gate.actions?(conn, %{})
    after
      :code.purge(gate)
      {:module, ^gate} = :code.load_binary(gate, filename, binary)
      :code.purge(gate)
      Code.compiler_options(options)
    end

    assert gate.actions?(conn, %{})
    assert A8Gate.actions?(conn, %{})
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

defmodule DawarichWeb.A12f3aORouteClosureTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{Router, Strangler}
  @endpoint DawarichWeb.Endpoint

  @moduletag :tmp_dir
  setup ctx do
    RailsUser.insert!(%{
      id: 8896,
      email: "o-routing@example.test",
      active_until: ~N[3026-10-03 12:00:00],
      plan: 1,
      visits_redetected_at: nil
    })

    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

    for {key, value} <- [
          jobs_repo: Repo,
          imports_repo: Repo,
          imports_storage: %{service: "local", root: ctx.tmp_dir},
          imports_services: %{"local" => %{service: "local", root: ctx.tmp_dir}}
        ] do
      previous = Application.fetch_env(:dawarich, key)
      Application.put_env(:dawarich, key, value)

      on_exit(fn ->
        case previous do
          {:ok, old} -> Application.put_env(:dawarich, key, old)
          :error -> Application.delete_env(:dawarich, key)
        end
      end)
    end

    upstream = upstream!()
    saved = Application.get_env(:dawarich, :rails_routes, [])
    mode = System.get_env("SELF_HOSTED")
    standalone = System.get_env("DAWARICH_RAILS")
    Application.put_env(:dawarich, :rails_routes, [])
    System.delete_env("DAWARICH_RAILS")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_routes, saved)
      restore_env("SELF_HOSTED", mode)
      restore_env("DAWARICH_RAILS", standalone)
    end)

    session = RailsUser.session(8896)
    %{upstream: upstream, session: session, token: DawarichWeb.RailsCsrf.masked_token(session)}
  end

  @tag a12f3a_o06: true
  test "O06: every Q M W P method is native and each source key restores raw pre-effect Rails routing",
       ctx do
    routes = q_m_w_p()
    assert length(routes) == 40
    ctx = seed_routes(ctx)
    System.put_env("SELF_HOSTED", "true")

    for {method, path, key, _} <- routes do
      pinned(ctx, method, path, key)
      if method == "GET", do: pinned(ctx, "HEAD", path, key)
    end

    for hosted <- ["true", "false"], legacy <- [false, true] do
      System.put_env("SELF_HOSTED", hosted)
      Repo.query!("UPDATE users SET settings=$1 WHERE id=8896", [if(legacy, do: [], else: %{})])

      for {method, path, key, owner} <- routes do
        route = info(method, path)
        assert route != :error, "#{method} #{path}"
        assert owner(route) == owner, "#{method} #{path}"
        assert Code.ensure_loaded?(owner)
        replay_only(ctx, method, path <> "?raw=a%2Bb&raw=c", key)
        if method == "GET", do: replay_only(ctx, "HEAD", path, key)
      end
    end

    Repo.query!("UPDATE users SET settings='{}' WHERE id=8896")
    Application.put_env(:dawarich, :rails_routes, ["stats", "digests"])

    for path <- ["/shared/month/missing", "/shared/digest/missing"], method <- [:get, :head] do
      assert info("GET", path).rails_key == "shared"
      response = dispatch(build_conn(), @endpoint, method, path, nil)
      assert response.status == 302
      assert get_resp_header(response, "location") == ["http://www.example.com/"]
      assert response.resp_body == ""
    end

    Application.put_env(:dawarich, :rails_routes, ["map"])

    for {method, path, key, _} <- routes, key in ~w(points tracks areas), method != "GET" do
      admitted = Strangler.call(raw(ctx, method, path, ""), [])
      refute admitted.halted, "map must leave #{key} independent"
    end

    Application.put_env(:dawarich, :rails_routes, [])

    for {method, path} <- [{:put, "/stats/2024/3/update"}, {:post, "/digests"}] do
      response =
        dispatch(
          put_req_header(build_conn(), "content-type", "application/x-www-form-urlencoded"),
          @endpoint,
          method,
          path,
          ""
        )

      assert response.status == 302
      assert get_resp_header(response, "location") == ["http://www.example.com/users/sign_in"]
    end

    for method <- [:get, :head] do
      response = dispatch(build_conn(), @endpoint, method, "/map/v1?date=2024-03-01", nil)
      assert response.status == 301

      assert get_resp_header(response, "location") == [
               "http://www.example.com/map/v2?date=2024-03-01"
             ]

      if method == :head, do: assert(response.resp_body == "")
    end
  end

  @tag a12f3a_o07: true
  test "O07: import export trip visit video methods consume native owner outcomes exactly once",
       ctx do
    assert Strangler.gate_open?(
             info("GET", "/settings/users/export"),
             raw(ctx, "HEAD", "/settings/users/export", "")
           )

    routes = i_f_e_t_v_r()
    assert length(routes) == 43
    ctx = seed_routes(ctx)
    System.put_env("SELF_HOSTED", "true")

    for {method, path, key, _} <- routes do
      pinned(ctx, method, path, key)
      if method == "GET", do: pinned(ctx, "HEAD", path, key)
    end

    for hosted <- ["true", "false"], legacy <- [false, true] do
      System.put_env("SELF_HOSTED", hosted)
      Repo.query!("UPDATE users SET settings=$1 WHERE id=8896", [if(legacy, do: [], else: %{})])

      for {method, path, key, handler} <- routes do
        route = info(method, path)
        assert route != :error, "#{method} #{path}"
        assert owner(route) == handler, "#{method} #{path}"
        assert Code.ensure_loaded?(handler)
        replay_only(ctx, method, path <> "?original=a%2Bb&original=c", key)
        if method == "GET", do: replay_only(ctx, "HEAD", path, key)
      end
    end

    Repo.query!("UPDATE users SET settings='{}' WHERE id=8896")
    Dawarich.Jobs.Ownership.put!(Repo, "command:users.export_data", :oban)

    expected =
      File.read!("test/fixtures/user_data/http.json")
      |> Jason.decode!()
      |> get_in(["en", "export"])

    for hosted <- ["true", "false"], method <- ["GET", "HEAD"] do
      System.put_env("SELF_HOSTED", hosted)
      if hosted == "false", do: pinned(ctx, method, "/settings/users/export", "user_data")
      before = Repo.query!("SELECT count(*) FROM job_outbox").rows

      response =
        @endpoint.call(raw(ctx, method, "/settings/users/export", ""), @endpoint.init([]))

      assert response.status == expected["status"]

      assert get_resp_header(response, "location") == [
               "http://www.example.com" <> expected["location"]
             ]

      assert get_resp_header(response, "x-dawarich-handler") == ["phoenix-user-data"]
      assert response.resp_body == ""
      assert [[count]] = before
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[count + 1]]
      assert commands() == []
      assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    end

    for key <- ~w(user_data visits) do
      Application.put_env(:dawarich, :rails_routes, [key])
      admitted = Strangler.call(raw(ctx, "PATCH", "/settings/visits", ""), [])
      refute admitted.halted
    end

    Application.put_env(:dawarich, :rails_routes, [])

    before = Repo.query!("SELECT count(*) FROM job_outbox").rows

    doomed =
      raw(ctx, "GET", "/settings/users/export", "")
      |> register_before_send(fn _ -> raise "synthetic post-commit response failure" end)

    error = assert_raise RuntimeError, fn -> @endpoint.call(doomed, @endpoint.init([])) end
    assert Exception.message(error) =~ "synthetic post-commit response failure"
    assert [[count]] = before
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[count + 1]]
    assert commands() == []
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)

    for {method, path, headers, bytes} <- [
          {"POST", "/route_videos", [], "foreign_domain=x"},
          {"POST", "/trips", [{"x-http-method-override", "DELETE"}], "trip%5Bname%5D=Synthetic"},
          {"POST", "/settings/users/import", [], "archive=bad&authenticity_token=bad"},
          {"POST", "/exports", [], "authenticity_token=bad"}
        ] do
      System.put_env("SELF_HOSTED", "true")
      previous = observations()

      conn =
        Enum.reduce(headers, raw(ctx, method, path, bytes), fn {k, v}, c ->
          put_req_header(c, k, v)
        end)

      {{line, original}, response} =
        forwarded(ctx.upstream, fn -> @endpoint.call(conn, @endpoint.init([])) end)

      assert response.status == 204
      assert line == "#{method} #{path} HTTP/1.1"
      assert original == bytes
      assert observations() == previous
    end

    System.put_env("DAWARICH_RAILS", "off")

    response =
      @endpoint.call(raw(ctx, "POST", "/route_videos", "foreign_domain=x"), @endpoint.init([]))

    assert response.status in [400, 422, 500]
    assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
    assert commands() == []
  end

  defp i_f_e_t_v_r do
    reads = [
      {"/imports", "imports", DawarichWeb.ImportsLive.Index},
      {"/imports/new", "imports", DawarichWeb.ImportsLive.New},
      {"/imports/42", "imports", DawarichWeb.ImportsLive.Show},
      {"/imports/42/edit", "imports", DawarichWeb.ImportsLive.Edit},
      {"/imports/42/download", "imports", DawarichWeb.ImportsDownload},
      {"/exports", "exports", DawarichWeb.ExportsLive.Index},
      {"/settings/users/export", "user_data", DawarichWeb.UserDataController},
      {"/trips", "trips", DawarichWeb.TripsLive.Index},
      {"/trips/new", "trips", DawarichWeb.TripsLive.Form},
      {"/trips/42", "trips", DawarichWeb.TripsLive.Show},
      {"/trips/42/edit", "trips", DawarichWeb.TripsLive.Form},
      {"/visits", "visits", DawarichWeb.VisitsNavigation},
      {"/settings/visits", "settings", DawarichWeb.SettingsLive.Visits}
    ]

    Enum.map(reads, fn {path, key, handler} -> {"GET", path, key, handler} end) ++
      [
        {"POST", "/imports", "imports", DawarichWeb.ImportsController},
        {"PATCH", "/imports/42", "imports", DawarichWeb.ImportsController},
        {"PUT", "/imports/42", "imports", DawarichWeb.ImportsController},
        {"DELETE", "/imports/42", "imports", DawarichWeb.ImportsController},
        {"POST", "/imports/42/extraction", "imports", DawarichWeb.ImportsController},
        {"DELETE", "/imports/42/extraction", "imports", DawarichWeb.ImportsController},
        {"POST", "/exports", "exports", DawarichWeb.ExportsCreate},
        {"DELETE", "/exports/42", "exports", DawarichWeb.ExportsDelete},
        {"POST", "/settings/users/import", "user_data", DawarichWeb.UserDataController},
        {"POST", "/trips", "trips", DawarichWeb.TripActions},
        {"PATCH", "/trips/42", "trips", DawarichWeb.TripActions},
        {"PUT", "/trips/42", "trips", DawarichWeb.TripActions},
        {"DELETE", "/trips/42", "trips", DawarichWeb.TripActions},
        {"POST", "/trips/42/recalculate", "trips", DawarichWeb.TripActions},
        {"POST", "/trips/42/export", "trips", DawarichWeb.TripActions},
        {"POST", "/trips/41/notes", "trips", DawarichWeb.TripNoteActions},
        {"PATCH", "/trips/41/notes/42", "trips", DawarichWeb.TripNoteActions},
        {"PUT", "/trips/41/notes/42", "trips", DawarichWeb.TripNoteActions},
        {"DELETE", "/trips/41/notes/42", "trips", DawarichWeb.TripNoteActions},
        {"PATCH", "/visits/42", "visits", DawarichWeb.VisitActions},
        {"PUT", "/visits/42", "visits", DawarichWeb.VisitActions},
        {"DELETE", "/visits/42", "visits", DawarichWeb.VisitActions},
        {"PATCH", "/visits/bulk_update", "visits", DawarichWeb.VisitActions},
        {"DELETE", "/visits/bulk_destroy", "visits", DawarichWeb.VisitActions},
        {"POST", "/visits/merge", "visits", DawarichWeb.VisitActions},
        {"POST", "/visits/redetections", "visits", DawarichWeb.VisitSettingsActions},
        {"PATCH", "/settings/visits", "settings", DawarichWeb.VisitSettingsActions},
        {"PUT", "/settings/visits", "settings", DawarichWeb.VisitSettingsActions},
        {"POST", "/route_videos", "route_videos", DawarichWeb.RouteVideoActions},
        {"DELETE", "/route_videos/42", "route_videos", DawarichWeb.RouteVideoActions}
      ]
  end

  defp q_m_w_p do
    reads = [
      {"/stats", "stats", DawarichWeb.StatsLive.Index},
      {"/stats/2024", "stats", DawarichWeb.StatsLive.Year},
      {"/stats/2024/3", "stats", DawarichWeb.StatsLive.Month},
      {"/digests", "digests", DawarichWeb.DigestsLive.Index},
      {"/digests/2024", "digests", DawarichWeb.DigestsLive.Show},
      {"/insights", "insights", DawarichWeb.InsightsLive.Index},
      {"/insights/details", "insights", DawarichWeb.InsightsLive.Details},
      {"/shared/month/synthetic", "shared", DawarichWeb.SharedStatsPage},
      {"/shared/digest/synthetic", "shared", DawarichWeb.SharedStatsPage},
      {"/map", "map", DawarichWeb.MapLive},
      {"/map/v2", "map", DawarichWeb.MapLive},
      {"/map/v1", "map", DawarichWeb.MapRedirects},
      {"/maps/v2", "map", DawarichWeb.MapRedirects},
      {"/map/timeline_feeds", "map", DawarichWeb.MapFrames},
      {"/map/timeline_feeds/calendar", "map", DawarichWeb.MapFrames},
      {"/map/residency", "map", DawarichWeb.MapFrames},
      {"/map/timeline_feeds/42/track_info", "map", DawarichWeb.MapFrames},
      {"/points", "points", DawarichWeb.PointsLive.Index},
      {"/points/42/address", "points", DawarichWeb.PointAddress},
      {"/tracks/41/segments", "tracks", DawarichWeb.MapFrames},
      {"/places", "places", DawarichWeb.PlacesLive.Index},
      {"/places/42", "places", DawarichWeb.PlaceNavigation},
      {"/places/nearby", "places", DawarichWeb.PlaceNavigation}
    ]

    Enum.map(reads, fn {path, key, handler} -> {"GET", path, key, handler} end) ++
      [
        {"PUT", "/stats/2024/3/update", "stats", DawarichWeb.StatsActions},
        {"PUT", "/stats/update_all", "stats", DawarichWeb.StatsActions},
        {"PATCH", "/stats/2024/3/sharing", "stats", DawarichWeb.StatSharing},
        {"POST", "/digests", "digests", DawarichWeb.DigestActions},
        {"DELETE", "/digests/2024", "digests", DawarichWeb.DigestActions},
        {"PATCH", "/digests/2024/sharing", "digests", DawarichWeb.DigestSharing},
        {"POST", "/areas", "areas", DawarichWeb.AreaActions},
        {"PATCH", "/areas/42", "areas", DawarichWeb.AreaActions},
        {"PUT", "/areas/42", "areas", DawarichWeb.AreaActions},
        {"PATCH", "/tracks/41/segments/42", "tracks", DawarichWeb.SegmentActions},
        {"PUT", "/tracks/41/segments/42", "tracks", DawarichWeb.SegmentActions},
        {"POST", "/tracks/recalculation", "tracks", DawarichWeb.TrackRecalculationActions},
        {"DELETE", "/points/bulk_destroy", "points", DawarichWeb.PointListActions},
        {"POST", "/places", "places", DawarichWeb.PlaceActions},
        {"PATCH", "/places/42", "places", DawarichWeb.PlaceActions},
        {"PUT", "/places/42", "places", DawarichWeb.PlaceActions},
        {"DELETE", "/places/42", "places", DawarichWeb.PlaceActions}
      ]
  end

  defp info(method, path), do: Phoenix.Router.route_info(Router, method, path, "www.example.com")
  defp owner(%{phoenix_live_view: {view, _, _, _}}), do: view
  defp owner(route), do: route.plug

  defp pinned(ctx, method, path, key) do
    {path, body, headers} = eligible(ctx, method, path)

    original =
      Enum.reduce(headers, raw(ctx, method, path, body), fn {k, v}, c ->
        put_req_header(c, k, v)
      end)

    build = fn -> original end
    Application.put_env(:dawarich, :rails_routes, [])
    route = info(if(method == "HEAD", do: "GET", else: method), path |> String.split("?") |> hd())
    assert Strangler.gate_open?(route, build.()), "native eligibility: #{method} #{path}"
    before = observations()

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               Repo.query!("SAVEPOINT native_probe")
               response = native_response(ctx, build.())

               assert response.status in [200, 301, 302, 303],
                      "native status: #{method} #{path}: #{response.status}"

               assert response.private[:dawarich_method] == method
               assert {:error, :timeout} = :gen_tcp.accept(ctx.upstream.listen, 0)
               if method == "HEAD", do: assert(response.resp_body == "")
               Repo.query!("ROLLBACK TO SAVEPOINT native_probe")
               Repo.query!("RELEASE SAVEPOINT native_probe")
               :ok
             end)

    assert observations() == before, "native probe restored: #{method} #{path}"
    before = observations()
    Application.put_env(:dawarich, :rails_routes, [key])

    {{line, bytes}, response} =
      forwarded(ctx.upstream, fn ->
        response = @endpoint.call(build.(), @endpoint.init([]))
        assert response.status == 204, "rollback #{key}: #{method} #{path}"
        response
      end)

    assert line == "#{method} #{path} HTTP/1.1"
    assert bytes == body
    assert response.status == 204
    refute response.private[:dawarich_method]
    assert observations() == before
    Application.put_env(:dawarich, :rails_routes, [])
  end

  defp native_response(ctx, original) do
    server =
      Task.async(fn ->
        alias Dawarich.Test.RawHTTP
        socket = RawHTTP.accept(ctx.upstream)
        {head, rest} = RawHTTP.read_head(socket)
        size = head |> RawHTTP.header("content-length") |> List.first("0") |> String.to_integer()
        RawHTTP.read_at_least(socket, rest, size)
        RawHTTP.reply(socket, "HTTP/1.1 204 No Content\r\n\r\n")
        :replayed
      end)

    try do
      response = @endpoint.call(original, @endpoint.init([]))

      refute response.status == 204,
             "unexpected Rails replay: #{original.method} #{original.request_path}"

      response
    after
      Task.shutdown(server)
    end
  end

  defp replay_only(ctx, method, path, key) do
    before = observations()
    Application.put_env(:dawarich, :rails_routes, [key])
    body = "original=%2B+%26&original=second&nested%5Ba%5D=1"

    {{line, bytes}, response} =
      forwarded(ctx.upstream, fn ->
        @endpoint.call(raw(ctx, method, path, body), @endpoint.init([]))
      end)

    assert line == "#{method} #{path} HTTP/1.1"
    assert bytes == body
    assert response.status == 204
    assert observations() == before
    Application.put_env(:dawarich, :rails_routes, [])
  end

  defp seed_routes(ctx) do
    alias Dawarich.Test.{FrameSeeds, TripsSeeds, ImportsExportsSeeds}

    for type <-
          ~w(stats.calculate_month stats.full_recalculation digests.calculate_year areas.relabel_visits transportation.user_reclassify transportation.reclassify_track tracks.recalculate achievements.check places.name_fetch places.delete_if_orphan places.bulk_name_fetch imports.process_gpx imports.process_normal imports.destroy enhanced_import.extract_gpx enhanced_import.destroy_gpx exports.points users.export_data users.import_data trips.calculate visits.suggest visits.full_history_redetect visits.months_changed) do
      Dawarich.Jobs.Ownership.put!(Repo, "command:" <> type, :oban)
    end

    FrameSeeds.stat!(8896, 2024, 3)

    Repo.query!(
      "INSERT INTO digests(user_id,year,period_type,toponyms,created_at,updated_at) VALUES(8896,2024,1,'[]',now(),now())"
    )

    Repo.query!(
      "INSERT INTO areas(id,user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES(42,8896,'Synthetic',51.34,12.37,200,now(),now())"
    )

    FrameSeeds.place!(8896, 42, "Synthetic")
    FrameSeeds.tag!(8896, 42, "Synthetic", 42, ~N[2026-10-03 10:00:00])

    FrameSeeds.track!(8896, 41, %{
      start_at: ~N[2026-10-03 09:00:00],
      end_at: ~N[2026-10-03 09:10:00]
    })

    FrameSeeds.segment!(41, 42, %{
      start_index: 0,
      end_index: 1,
      start_at: ~U[2026-10-03 09:00:00Z],
      end_at: ~U[2026-10-03 09:10:00Z],
      distance: 1000,
      duration: 600
    })

    FrameSeeds.point!(8896, 42, 1_791_015_000, %{country_name: "Germany"})

    for id <- [42, 43],
        do:
          FrameSeeds.visit!(8896, id, %{
            started_at: NaiveDateTime.add(~N[2026-10-03 09:00:00], (id - 42) * 3600),
            ended_at: NaiveDateTime.add(~N[2026-10-03 09:30:00], (id - 42) * 3600),
            place_id: 42
          })

    for id <- [41, 42],
        do: TripsSeeds.trip!(%{id: id, user_id: 8896, path: [[12.37, 51.33], [12.38, 51.34]]})

    TripsSeeds.note!(%{
      id: 42,
      trip_id: 41,
      user_id: 8896,
      body: "Synthetic",
      noted_at: ~N[2026-10-03 09:00:00]
    })

    TripsSeeds.route_video!(%{
      id: 42,
      user_id: 8896,
      name: "Synthetic",
      status: 1,
      settings: %{},
      created_at: ~N[2026-10-03 09:00:00]
    })

    ImportsExportsSeeds.import!(%{
      id: 42,
      user_id: 8896,
      name: "Synthetic.gpx",
      raw_data: %{"waypoints_seen" => 1},
      additional_data_extraction_status: 3
    })

    ImportsExportsSeeds.export!(%{id: 42, user_id: 8896})
    blob = Dawarich.RailsBlobFixture.create!(Repo, ctx.tmp_dir, "Synthetic-upload.gpx", "<gpx/>")

    Repo.query!(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',42,$1,now())",
      [blob.id]
    )

    upload = Dawarich.RailsBlobFixture.create!(Repo, ctx.tmp_dir, "Synthetic-new.gpx", "<gpx/>")

    archive =
      Dawarich.RailsBlobFixture.create!(Repo, ctx.tmp_dir, "Synthetic.zip", "Synthetic",
        content_type: "application/zip"
      )

    for reference <- [upload, archive],
        do: Dawarich.Storage.UploadReceipts.bind!(Repo, reference.id, 8896)

    video =
      Dawarich.RailsBlobFixture.create!(Repo, ctx.tmp_dir, "Synthetic.mp4", "Synthetic",
        content_type: "video/mp4",
        metadata: %{"identified" => true, "analyzed" => true}
      )

    Map.merge(ctx, %{blob: upload.signed_id, archive: archive.signed_id, video: video.signed_id})
  end

  defp eligible(_ctx, method, path) when method in ["GET", "HEAD"] do
    path =
      if path == "/map/timeline_feeds/42/track_info",
        do: "/map/timeline_feeds/41/track_info",
        else: path

    path =
      if path == "/places/nearby",
        do: path <> "?latitude=51.34&longitude=12.37&radius=0.5",
        else: path

    {path, "", []}
  end

  defp eligible(ctx, method, path) do
    attrs =
      case {method, path} do
        {_, "/areas" <> _} ->
          %{
            "name" => "Synthetic + &",
            "latitude" => "51.34",
            "longitude" => "12.37",
            "radius" => "300"
          }

        {_, "/tracks/41/segments/42"} ->
          %{"track_segment" => %{"transportation_mode" => "walking"}}

        {_, "/points/bulk_destroy"} ->
          %{"point_ids" => ["42"]}

        {m, "/places" <> _} when m != "DELETE" ->
          %{
            "place" => %{"name" => "Synthetic + &", "latitude" => "51.34", "longitude" => "12.37"}
          }

        {_, "/digests"} ->
          %{"year" => "2023"}

        {_, "/stats/2024/3/sharing"} ->
          %{"enabled" => "1"}

        {_, "/digests/2024/sharing"} ->
          %{"enabled" => "1"}

        {_, "/imports"} ->
          %{"import" => %{"files" => [ctx.blob]}}

        {m, "/imports/42"} when m in ["PATCH", "PUT"] ->
          %{"import" => %{"name" => "Synthetic + &.gpx"}}

        {_, "/exports"} ->
          %{"file_format" => "json", "start_at" => "2026-10-01", "end_at" => "2026-10-03"}

        {_, "/settings/users/import"} ->
          %{"archive" => ctx.archive}

        {_, "/trips"} ->
          %{
            "trip" => %{
              "name" => "Synthetic + &",
              "started_at" => "2026-10-01T09:00",
              "ended_at" => "2026-10-02T09:00"
            }
          }

        {m, "/trips/42"} when m != "DELETE" ->
          %{"trip" => %{"name" => "Synthetic + &"}}

        {_, "/trips/42/export"} ->
          %{"file_format" => "gpx"}

        {m, "/trips/41/notes" <> _} when m != "DELETE" ->
          %{"note" => %{"body" => "<p>Synthetic + &</p>", "date" => "2026-10-03T09:00"}}

        {_, "/visits/bulk_update"} ->
          %{"visit_ids" => ["42"], "status" => "confirmed"}

        {_, "/visits/bulk_destroy"} ->
          %{"visit_ids" => ["42"]}

        {_, "/visits/merge"} ->
          %{"visit_ids" => ["42", "43"]}

        {m, "/visits/42"} when m != "DELETE" ->
          %{"visit" => %{"name" => "Synthetic + &"}}

        {_, "/settings/visits"} ->
          %{"settings" => %{"visit_radius_meters" => "75"}}

        {_, "/route_videos"} ->
          %{"route_video" => %{"name" => "Synthetic + &", "file" => ctx.video}}

        _ ->
          %{}
      end

    headers =
      if path == "/places" or String.starts_with?(path, "/areas") or
           String.contains?(path, "/segments/") or String.ends_with?(path, "/sharing"),
         do: [{"accept", "text/vnd.turbo-stream.html"}],
         else: []

    {path, Plug.Conn.Query.encode(Map.put(attrs, "authenticity_token", ctx.token)), headers}
  end

  defp raw(ctx, method, path, body) do
    Plug.Test.conn(method, path, body)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("accept", "text/html")
  end

  defp observations do
    tables =
      ~w(stats digests areas trips places visits route_videos imports exports points tags track_segments job_outbox)

    columns =
      for table <-
            tables ++
              ~w(users notes taggings active_storage_blobs active_storage_attachments phoenix.rails_commands),
          do:
            "(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text), '[]'::jsonb) FROM #{table} t)"

    Repo.query!("SELECT " <> Enum.join(columns, ",")).rows
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end

defmodule DawarichWeb.A12f3aOEdHandoffTest do
  use ExUnit.Case, async: true

  @tag a12f3a_o08_review: true
  test "R2: row 24 can reconcile every historical ED by branch, disposition, evidence and prerequisite" do
    ledger = File.read!(Path.expand("../../../docs/phoenix/a12f3a-closure.md", __DIR__))

    for id <- ~w(119 152 194 212 249 295 335 355 370 383 392 400 410 411) do
      rows = ledger |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "| ED-#{id} |"))
      assert length(rows) == 1, "one actionable mapping required for ED-#{id}"
      [row] = rows
      cells = row |> String.split("|") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      assert ["ED-" <> ^id, branch, disposition, evidence, prerequisite] = cells
      assert byte_size(branch) > 10
      assert disposition =~ ~r/\A(No change proposed|Propose bounded native)/
      assert evidence =~ "`"
      assert byte_size(prerequisite) > 10
    end
  end
end
