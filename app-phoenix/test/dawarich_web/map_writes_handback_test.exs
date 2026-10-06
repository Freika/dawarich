defmodule DawarichWeb.MapWritesHandbackTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsFormRequests, RailsUser}
  alias DawarichWeb.{RailsCsrf, Router}
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    Repo.query!("CREATE SCHEMA IF NOT EXISTS phoenix")

    Repo.query!(File.read!("priv/repo/sql/20260928130000_rails_commands.sql"), [],
      query_type: :text
    )

    user = FrameSeeds.user!(92001, %{"timezone" => "UTC"}, %{points_count: 1})
    FrameSeeds.point!(user.id, 920_010, 1_791_021_600)

    FrameSeeds.track!(user.id, 920_010, %{
      start_at: ~N[2026-10-03 09:00:00],
      end_at: ~N[2026-10-03 09:10:00]
    })

    FrameSeeds.segment!(920_010, 9_200_100, %{
      start_at: ~U[2026-10-03 09:00:00Z],
      end_at: ~U[2026-10-03 09:10:00Z],
      transportation_mode: 2,
      duration: 600,
      distance: 1000
    })

    Repo.insert_all("tags", [
      %{
        id: 920_010,
        user_id: user.id,
        name: "Synthetic",
        created_at: ~N[2026-10-02 10:00:00],
        updated_at: ~N[2026-10-02 10:00:00]
      }
    ])

    old = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, old) end)
    upstream = RailsFormRequests.upstream!()
    %{user: user, session: RailsUser.session(user.id), upstream: upstream}
  end

  defp request(ctx, method, path, raw, headers \\ [], session \\ nil) do
    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session || ctx.session))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> put_req_header("accept", "text/html")

    conn =
      Enum.reduce(headers, conn, fn {name, value}, conn -> put_req_header(conn, name, value) end)

    dispatch(conn, @endpoint, method, path, raw)
  end

  defp snapshot do
    pages =
      for table <- ~w(points tags taggings tracks track_segments),
          do: Repo.query!("SELECT to_jsonb(t)::text FROM #{table} t ORDER BY id").rows

    counters = Repo.query!("SELECT id,points_count,updated_at FROM users ORDER BY id").rows
    imports = Repo.query!("SELECT id,points_count,updated_at FROM imports ORDER BY id").rows
    effects = Repo.query!("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id").rows

    jobs =
      Dawarich.Jobs.repo().query!(
        "SELECT (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM oban.oban_jobs), (SELECT count(*) FROM phoenix.rails_commands)"
      ).rows

    {pages, counters, imports, effects, jobs}
  end

  defp raw(ctx, suffix),
    do:
      "authenticity_token=" <>
        URI.encode_www_form(RailsCsrf.masked_token(ctx.session)) <> "&" <> suffix

  defp forwarded(ctx, method, path, body, headers \\ [], session \\ nil) do
    before = snapshot()

    {{line, bytes}, conn} =
      RailsFormRequests.forwarded(ctx.upstream, fn ->
        request(ctx, method, path, body, headers, session)
      end)

    assert line == "#{method |> Atom.to_string() |> String.upcase()} #{path} HTTP/1.1"
    assert bytes == body
    assert conn.status == 204
    assert get_resp_header(conn, "set-cookie") == []
    assert Map.has_key?(conn.private, :dawarich_rails_session_changes) == false
    assert snapshot() == before
  end

  test "Unicode radius numeric whitespace returns the Rails recorded endpoint error", ctx do
    body = raw(ctx, "tag[name]=Radius&tag[privacy_radius_meters]=%C2%A01%C2%A0")
    response = request(ctx, :post, "/tags", body)

    state =
      File.read!("test/fixtures/map_writes/tags/radius_unicode_space.json") |> Jason.decode!()

    assert response.status == state["status"]
    assert response.resp_body =~ hd(state["validation"]["errors"])["message"]
    assert Repo.query!("SELECT count(*) FROM tags WHERE name='Radius'").rows == [[0]]
  end

  test "high precision radius endpoint accepts Rails rounded numericality", ctx do
    for name <- ~w(radius_precision_limit radius_precision_exponent) do
      state = File.read!("test/fixtures/map_writes/tags/#{name}.json") |> Jason.decode!()
      radius = state["validation"]["raw_radius"]

      body =
        raw(ctx, "tag[name]=#{name}&tag[privacy_radius_meters]=#{URI.encode_www_form(radius)}")

      response = request(ctx, :post, "/tags", body)
      assert response.status == state["status"]

      assert Repo.query!("SELECT privacy_radius_meters FROM tags WHERE name=$1", [name]).rows ==
               [[state["validation"]["cast_radius"]]]
    end
  end

  test "unowned query format session token override shapes forward bytes", ctx do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    probe = request(ctx, :post, "/tags", "authenticity_token=BAD&tag[name]=Synthetic-new")
    assert probe.status == 502
    assert Repo.query!("SELECT name FROM tags ORDER BY id").rows == [["Synthetic"]]

    mismatch =
      request(ctx, :post, "/tags", raw(ctx, "tag[name]=Synthetic-new"), [{"x-csrf-token", "BAD"}])

    assert mismatch.status == 502
    assert Repo.query!("SELECT name FROM tags ORDER BY id").rows == [["Synthetic"]]

    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    for {path, body, headers, session} <- [
          {"/tags?locale=de", raw(ctx, "tag[name]=Changed"), [], nil},
          {"/tags", raw(ctx, "tag[name]=Changed"), [{"accept", "application/json"}], nil},
          {"/tags", raw(ctx, "tag[name]=Changed"), [{"x-http-method-override", "PATCH"}], nil},
          {"/tags", raw(ctx, "tag[name]=Changed"),
           [{"origin", "https://foreign.example.invalid"}], nil},
          {"/tags", "authenticity_token=BAD&tag[name]=Changed", [], nil},
          {"/tags", raw(ctx, "tag[name]=Changed&tag[name]=Other"), [], nil},
          {"/tags", raw(ctx, "tag[name]=%FF"), [], nil},
          {"/tags", raw(ctx, "tag[name]=Changed&tag[unknown]=1"), [], nil},
          {"/tags", raw(ctx, "tag[name]=Changed"), [],
           Map.delete(ctx.session, "warden.user.user.key")}
        ],
        do: forwarded(ctx, :post, path, body, headers, session)
  end

  test "keys forward native bodies once with no native store changes", ctx do
    before = snapshot()
    Application.put_env(:dawarich, :rails_routes, ["points"])
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    probe = request(ctx, :delete, "/points/bulk_destroy", raw(ctx, "point_ids[]=920010"))
    assert probe.status == 502
    assert snapshot() == before
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})

    for {key, method, path, body} <- [
          {"tags", :patch, "/tags/920010", raw(ctx, "tag[name]=Changed")},
          {"tracks", :patch, "/tracks/920010/segments/9200100",
           raw(ctx, "track_segment[transportation_mode]=cycling")},
          {"points", :delete, "/points/bulk_destroy", raw(ctx, "point_ids[]=920010")}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])
      forwarded(ctx, method, path, body)
      forwarded(ctx, :post, path, "_method=#{method}&" <> body)
    end
  end

  test "new writes preserve A4 A8 unrelated track ownership", ctx do
    assert Phoenix.Router.route_info(Router, "GET", "/tracks/920010", "www.example.com") == :error

    for {method, path} <- [
          {"GET", "/api/v1/tracks/920010"},
          {"PATCH", "/visits/920010"},
          {"POST", "/visits/bulk_destroy"}
        ] do
      route = Phoenix.Router.route_info(Router, method, path, "www.example.com")
      assert route != :error
      refute :map_write in route.pipe_through
    end

    forwarded(ctx, :patch, "/api/v1/tracks/920010", raw(ctx, "track[distance]=500"))

    route =
      Phoenix.Router.route_info(
        Router,
        "PUT",
        "/tracks/920010/segments/9200100",
        "www.example.com"
      )

    assert route.plug == DawarichWeb.SegmentActions
    assert route.pipe_through == [:map_write]
  end

  test "rejected write commits no cookie outbox RailsCommands", ctx do
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})
    probe = request(ctx, :post, "/tags", raw(ctx, "tag[name]=Changed&tag[unknown]=1"))
    assert probe.status == 502
    assert get_resp_header(probe, "set-cookie") == []
    assert Map.has_key?(probe.private, :dawarich_rails_session_changes) == false
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, ctx.upstream.port})
    forwarded(ctx, :post, "/tags", raw(ctx, "tag[name]=Changed&tag[unknown]=1"))
    forwarded(ctx, :patch, "/tracks/920010/segments/9200100", raw(ctx, "reset=true&unknown=1"))
    forwarded(ctx, :delete, "/points/bulk_destroy?client=legacy", raw(ctx, "point_ids[]=920010"))
  end
end
