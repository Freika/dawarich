defmodule DawarichWeb.MapDataHandbackTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsFormRequests, RailsUser}
  alias DawarichWeb.Router
  @endpoint DawarichWeb.Endpoint
  @points "/points?start_at=1772359200&end_at=1772445600"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8380)

    FrameSeeds.track!(user.id, 8380, %{
      start_at: ~N[2026-10-03 08:00:00],
      end_at: ~N[2026-10-03 09:00:00]
    })

    FrameSeeds.point!(user.id, 838_001, 1_772_359_200)
    stamp = ~N[2026-10-03 10:00:00]

    Repo.insert_all("tags", [
      %{id: 83801, user_id: user.id, name: "Synthetic", created_at: stamp, updated_at: stamp}
    ])

    old = Application.get_env(:dawarich, :rails_routes)

    on_exit(fn ->
      if old,
        do: Application.put_env(:dawarich, :rails_routes, old),
        else: Application.delete_env(:dawarich, :rails_routes)
    end)

    %{user: user, upstream: RailsFormRequests.upstream!()}
  end

  defp changes do
    pages =
      Repo.query!(
        "SELECT (SELECT count(*) FROM points), (SELECT count(*) FROM tags), (SELECT count(*) FROM track_segments)"
      ).rows

    jobs =
      Dawarich.Jobs.repo().query!(
        "SELECT (SELECT count(*) FROM public.job_outbox), (SELECT count(*) FROM oban.oban_jobs), (SELECT count(*) FROM phoenix.rails_commands)"
      ).rows

    pages ++ jobs
  end

  test "hand-back snapshots observe jobs outside the page sandbox" do
    Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE", [], log: false)
    [[points, tags, segments], [outbox, jobs, commands]] = changes()

    outbox!(%{})

    ScratchRepo.query!(
      "INSERT INTO oban.oban_jobs(worker, args) VALUES ('Synthetic', '{}')",
      [],
      log: false
    )

    assert changes() == [[points, tags, segments], [outbox + 1, jobs + 1, commands]]
  end

  defp write(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded;charset=UTF-8")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> dispatch(@endpoint, method, path, body)
  end

  defp forwarded_write(upstream, user, method, path, body) do
    before = changes()

    {{line, raw}, conn} =
      RailsFormRequests.forwarded(upstream, fn ->
        RailsUser.signed_in(user.id) |> write(method, path, body)
      end)

    assert line == "#{method |> Atom.to_string() |> String.upcase()} #{path} HTTP/1.1"
    assert raw == body
    assert conn.status == 204
    assert get_resp_header(conn, "set-cookie") == []
    assert changes() == before
  end

  test "point bulk delete forwards method path query and raw body unchanged", %{
    user: user,
    upstream: upstream
  } do
    path = "/points/bulk_destroy?start_at=1772359200&end_at=1772445600&import_id=3&order_by=ASC"
    body = "point_ids%5B%5D=838001&point_ids%5B%5D=&authenticity_token=synthetic%2Btoken"
    forwarded_write(upstream, user, :delete, path, body)
    forwarded_write(upstream, user, :post, path, "_method=delete&" <> body)
  end

  test "unsupported tag create update delete and override posts remain Rails requests", %{
    user: user,
    upstream: upstream
  } do
    body =
      "tag%5Bname%5D=Synthetic+%26+Place&tag%5Bicon%5D=%F0%9F%8F%A0&tag%5Bprivacy_radius_meters%5D=250"

    forwarded_write(upstream, user, :post, "/tags", body)

    for method <- [:patch, :put, :delete] do
      forwarded_write(upstream, user, method, "/tags/83801?via=synthetic", body)
      forwarded_write(upstream, user, :post, "/tags/83801", "_method=#{method}&" <> body)
    end
  end

  test "unsupported segment PATCH reset and override posts remain Rails requests", %{
    user: user,
    upstream: upstream
  } do
    for body <- ["track_segment%5Btransportation_mode%5D=cycling", "reset=true"] do
      forwarded_write(upstream, user, :patch, "/tracks/8380/segments/83801?synthetic=x%2By", body)

      forwarded_write(
        upstream,
        user,
        :post,
        "/tracks/8380/segments/83801",
        "_method=patch&" <> body
      )
    end
  end

  test "points tags and tracks keys hand their owned GETs back", %{user: user, upstream: upstream} do
    for {key, paths} <- [
          {"points", [@points, "/points/838001/address"]},
          {"tags", ["/tags", "/tags/new", "/tags/83801/edit"]},
          {"tracks", ["/tracks/8380/segments"]}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])

      for path <- paths do
        {{line, raw}, conn} =
          RailsFormRequests.forwarded(upstream, fn ->
            RailsUser.signed_in(user.id)
            |> put_req_header("turbo-frame", "point-address-838001")
            |> get(path)
          end)

        assert line == "GET #{path} HTTP/1.1"
        assert raw == ""
        assert conn.status == 204
        assert get_resp_header(conn, "set-cookie") == []
      end
    end
  end

  test "map key alone does not hand back points tags or segment GETs", %{user: user} do
    Application.put_env(:dawarich, :rails_routes, ["map"])
    Application.put_env(:dawarich, :rails_upstream, nil)

    for path <- [
          @points,
          "/points/838001/address",
          "/tags",
          "/tags/new",
          "/tags/83801/edit",
          "/tracks/8380/segments"
        ] do
      conn =
        RailsUser.signed_in(user.id)
        |> put_req_header("turbo-frame", "point-address-838001")
        |> get(path)

      assert conn.status == 200, path
    end

    assert %{plug: Phoenix.LiveView.Plug} =
             Phoenix.Router.route_info(Router, "GET", "/places", "localhost")

    assert %{slice: :api_map_reads} =
             Phoenix.Router.route_info(Router, "GET", "/api/v1/tracks/8380", "localhost")

    assert Phoenix.Router.route_info(Router, "GET", "/tracks/8380", "localhost") == :error
  end

  test "unsupported page formats reach Rails without session side effects", %{
    user: user,
    upstream: upstream
  } do
    refute DawarichWeb.Strangler.page_request?(
             build_conn(:get, "/points")
             |> put_req_header("accept", "application/json")
           )

    flash = %{"discard" => [], "flashes" => %{"notice" => "Saved"}}

    for {path, headers} <- [
          {"/points", [{"accept", "application/json"}]},
          {"/points", [{"x-requested-with", "XMLHttpRequest"}]},
          {"/points.json", []},
          {"/points?format=json", []},
          {"/points?start_at[]=1", []},
          {"/tracks/8380/segments?via=x", []}
        ] do
      {{line, _}, conn} =
        RailsFormRequests.forwarded(upstream, fn ->
          Enum.reduce(headers, RailsUser.signed_in(user.id, %{"flash" => flash}), fn {key, value},
                                                                                     conn ->
            put_req_header(conn, key, value)
          end)
          |> get(path)
        end)

      assert line == "GET #{path} HTTP/1.1"
      assert conn.status == 204
      assert get_resp_header(conn, "set-cookie") == []
      refute Map.has_key?(conn.private, :dawarich_rails_session_changes)
    end
  end
end
