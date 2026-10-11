defmodule DawarichWeb.A8GateEndpointTest do
  use Dawarich.JobsCase
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{Repo, ScratchRepo}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    old_jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-a8-cloud-jwt")

    on_exit(fn ->
      if old_jwt,
        do: System.put_env("JWT_SECRET_KEY", old_jwt),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    previous = Map.new([:rails_routes, :jobs_repo], &{&1, Application.fetch_env(:dawarich, &1)})
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    Application.put_env(:dawarich, :rails_routes, [])

    on_exit(fn ->
      for {key, old} <- previous do
        case old do
          {:ok, value} -> Application.put_env(:dawarich, key, value)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    user =
      RailsUser.insert!(%{
        id: 894_000,
        email: "a8-gate@example.invalid",
        visits_redetected_at: nil
      })

    ScratchRepo.insert_all("users", [user])
    session = RailsUser.session(user.id)
    %{session: session, token: DawarichWeb.RailsCsrf.masked_token(session)}
  end

  for {name, method, path, body} <- [
        {"Cloud actions replay untouched before effects", :patch, "/visits/42",
         "visit%5Bname%5D=Original+bytes"},
        {"Cloud visits navigation stays native before effects", :get, "/visits?status=suggested",
         ""},
        {"Cloud settings replay untouched before auth", :get, "/settings/visits?locale=en", ""}
      ] do
    @tag cloud: method
    test name, ctx do
      old = System.get_env("SELF_HOSTED")
      System.put_env("SELF_HOSTED", "false")
      Application.put_env(:dawarich, :rails_routes, ["visits", "settings"])

      on_exit(fn ->
        if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
      end)

      if unquote(path) == "/visits?status=suggested" do
        conn = request(ctx, unquote(method), unquote(path), unquote(body))
        assert conn.status == 302

        assert get_resp_header(conn, "location") ==
                 ["http://www.example.com/map/v2?panel=timeline&date=today&status=suggested"]

        refute Map.has_key?(conn.assigns, :current_user)
        refute Map.has_key?(conn.assigns, :api_params)
        assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
        assert rows("SELECT count(*) FROM route_videos") == [[0]]
        assert rows("SELECT count(*) FROM visits") == [[0]]
      else
        replay(ctx, upstream!(), unquote(method), unquote(path), unquote(body))
      end
    end
  end

  defp request(ctx, method, path, body) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
    |> put_req_header(
      "accept",
      if(method == :get, do: "text/html", else: "text/vnd.turbo-stream.html")
    )
    |> put_req_header("x-csrf-token", ctx.token)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> Phoenix.ConnTest.dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  @tag limiter: :public
  test "A8 public pipeline runs the limiter", ctx do
    conn = request(ctx, :get, "/visits", "")
    assert conn.status == 302
    assert conn.private.dawarich_rate_limit == []
  end

  @tag limiter: :browser
  test "visits settings browser pipeline runs the limiter", ctx do
    conn = request(ctx, :get, "/settings/visits", "")
    assert conn.status == 200
    assert conn.private.dawarich_rate_limit == []
  end

  defp replay(ctx, upstream, method, path, body) do
    conn = request(ctx, method, path, body)

    expected =
      if method == :get or (method == :post and path == "/visits/bulk_update"), do: 200, else: 422

    assert conn.status == expected, "#{method} #{path}"
    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM route_videos") == [[0]]
    assert rows("SELECT count(*) FROM visits") == [[0]]
    conn
  end

  test "route video hand-back precedes the request pipeline", ctx do
    Application.put_env(:dawarich, :rails_routes, ["route_videos"])
    upstream = upstream!()

    for {method, path, body} <- [
          {:post, "/route_videos", "name=Original%20bytes&blob_signed_id=unsupported"},
          {:delete, "/route_videos/42", ""},
          {:post, "/route_videos/42", "_method=delete"},
          {:post, "/route_videos", "format=json&name=Original+bytes"}
        ] do
      replay(ctx, upstream, method, path, body)
    end
  end

  test "visits hand-back covers the visit actions and leaves the page to settings", ctx do
    Application.put_env(:dawarich, :rails_routes, ["visits"])
    upstream = upstream!()

    for {method, path, body} <- [
          {:patch, "/visits/42", "visit%5Bname%5D=Original+bytes"},
          {:put, "/visits/42", "visit%5Bname%5D=Original%20bytes"},
          {:delete, "/visits/42", ""},
          {:post, "/visits/42", "_method=delete"},
          {:patch, "/visits/bulk_update", "status=confirmed&visit_ids%5B%5D=42"},
          {:post, "/visits/bulk_update", "_method=patch&status=confirmed"},
          {:delete, "/visits/bulk_destroy", "visit_ids%5B%5D=42"},
          {:post, "/visits/bulk_destroy", "_method=delete&visit_ids%5B%5D=42"},
          {:post, "/visits/merge", "visit_ids%5B%5D=42&visit_ids%5B%5D=43"}
        ] do
      replay(ctx, upstream, method, path, body)
    end

    Application.put_env(:dawarich, :rails_routes, ["settings"])
    conn = request(ctx, :get, "/visits", "")
    assert conn.status == 302

    assert get_resp_header(conn, "location") ==
             ["http://www.example.com/map/v2?panel=timeline&date=today&status=confirmed"]
  end

  test "API and storage requests retain their assigned route ownership", ctx do
    for {method, path, module, action, pipeline} <- [
          {"POST", "/rails/active_storage/direct_uploads", DawarichWeb.StorageRoutes,
           :direct_upload, :storage_upload},
          {"GET", "/rails/active_storage/blobs/redirect/synthetic/movie.mp4",
           DawarichWeb.StorageRoutes, :redirect, :storage_public},
          {"GET", "/api/v1/visits", DawarichWeb.Api.VisitsController, :index, :api_visits},
          {"PATCH", "/api/v1/visits/42", DawarichWeb.Api.VisitsController, :update, :api_visits}
        ] do
      assert %{plug: ^module, plug_opts: ^action, pipe_through: [^pipeline]} =
               Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com")
    end

    missing = request(ctx, :get, "/api/v1/route_videos", "")
    assert missing.status == 404
    assert get_resp_header(missing, "set-cookie") == []

    for path <- ["/visits/not-a-number", "/visits/1234567890123456789", "/visits/42.json"] do
      refused = request(ctx, :post, path, "_method=delete")
      assert refused.status == 404
    end

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM route_videos") == [[0]]
    assert rows("SELECT count(*) FROM visits") == [[0]]
  end
end
