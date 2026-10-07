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

  setup do
    RailsUser.insert!(%{id: 8896, email: "o-routing@example.test"})
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

    %{upstream: upstream, session: RailsUser.session(8896)}
  end

  @tag a12f3a_o06: true
  test "O06: every Q M W P method is native and each source key restores raw pre-effect Rails routing",
       ctx do
    routes = q_m_w_p()
    assert length(routes) == 47

    for hosted <- ["true", "false"], legacy <- [false, true] do
      System.put_env("SELF_HOSTED", hosted)
      Repo.query!("UPDATE users SET settings=$1 WHERE id=8896", [if(legacy, do: [], else: %{})])

      for {method, path, key, owner} <- routes do
        route = info(method, path)
        assert route != :error, "#{method} #{path}"
        assert owner(route) == owner, "#{method} #{path}"
        assert Code.ensure_loaded?(owner)
        pinned(ctx, method, path <> "?raw=a%2Bb&raw=c", key)
        if method == "GET", do: pinned(ctx, "HEAD", path, key)
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

    for {method, path, key, _} <- routes, key in ~w(tags points tracks areas), method != "GET" do
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

    for hosted <- ["true", "false"], legacy <- [false, true] do
      System.put_env("SELF_HOSTED", hosted)
      Repo.query!("UPDATE users SET settings=$1 WHERE id=8896", [if(legacy, do: [], else: %{})])

      for {method, path, key, handler} <- routes do
        route = info(method, path)
        assert route != :error, "#{method} #{path}"
        assert owner(route) == handler, "#{method} #{path}"
        assert Code.ensure_loaded?(handler)
        if key == "user_data", do: assert(route.rails_key == key)
        pinned(ctx, method, path <> "?original=a%2Bb&original=c", key)
        if method == "GET", do: pinned(ctx, "HEAD", path, key)
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
      {"/tags", "tags", DawarichWeb.TagsLive.Index},
      {"/tags/new", "tags", DawarichWeb.TagsLive.Form},
      {"/tags/42/edit", "tags", DawarichWeb.TagsLive.Form},
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
        {"POST", "/tags", "tags", DawarichWeb.TagActions},
        {"PATCH", "/tags/42", "tags", DawarichWeb.TagActions},
        {"PUT", "/tags/42", "tags", DawarichWeb.TagActions},
        {"DELETE", "/tags/42", "tags", DawarichWeb.TagActions},
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

    counts = Enum.map(tables, &Repo.query!("SELECT count(*) FROM #{&1}").rows)
    {counts, commands()}
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
