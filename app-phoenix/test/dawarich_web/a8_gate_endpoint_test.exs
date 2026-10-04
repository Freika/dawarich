defmodule DawarichWeb.A8GateEndpointTest do
  use Dawarich.JobsCase
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.{Repo, ScratchRepo}
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
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
        {"Cloud navigation replays untouched before auth", :get, "/visits?status=suggested", ""},
        {"Cloud settings replay untouched before auth", :get, "/settings/visits?locale=en", ""}
      ] do
    @tag cloud: method
    test name, ctx do
      old = System.get_env("SELF_HOSTED")
      System.put_env("SELF_HOSTED", "false")

      on_exit(fn ->
        if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
      end)

      replay(ctx, upstream!(), unquote(method), unquote(path), unquote(body))
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

  @tag limiter: :action
  test "A8 action pipeline runs the limiter before parsing", ctx do
    conn = request(ctx, :patch, "/settings/visits", "settings%5Bvisit_radius_meters%5D=75")
    assert conn.status == 302
    assert conn.private.dawarich_rate_limit == []
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
    {{line, actual}, conn} = forwarded(upstream, fn -> request(ctx, method, path, body) end)
    assert line == "#{String.upcase(to_string(method))} #{path} HTTP/1.1"
    assert actual == body
    assert conn.status == 204
    refute Map.has_key?(conn.assigns, :current_user)
    refute Map.has_key?(conn.assigns, :api_params)
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

  test "visits hand-back includes redetections but settings is separate", ctx do
    Application.put_env(:dawarich, :rails_routes, ["visits"])
    upstream = upstream!()

    for {method, path, body} <- [
          {:get, "/visits?status=suggested", ""},
          {:post, "/visits/redetections", ""},
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

    conn =
      request(
        ctx,
        :post,
        "/settings/visits",
        "_method=patch&settings%5Bvisit_radius_meters%5D=75"
      )

    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/settings/visits"]
    assert rows("SELECT settings->>'visit_radius_meters' FROM users WHERE id=894000") == [["75"]]

    Application.put_env(:dawarich, :rails_routes, ["settings"])
    conn = request(ctx, :get, "/visits", "")
    assert conn.status == 302

    assert get_resp_header(conn, "location") ==
             ["http://www.example.com/map/v2?panel=timeline&date=today&status=confirmed"]
  end

  test "out-of-scope API and storage requests have unchanged route ownership", ctx do
    upstream = upstream!()

    for {method, path} <- [
          {:get, "/api/v1/route_videos"},
          {:get, "/api/v1/visits"},
          {:patch, "/api/v1/visits/42"},
          {:post, "/rails/active_storage/direct_uploads"},
          {:get, "/rails/active_storage/blobs/redirect/synthetic/movie.mp4"}
        ] do
      assert Phoenix.Router.route_info(
               DawarichWeb.Router,
               String.upcase(to_string(method)),
               path,
               "www.example.com"
             ) == :error

      replay(ctx, upstream, method, path, "")
    end

    route =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        "GET",
        "/api/v1/photos/synthetic/thumbnail",
        "www.example.com"
      )

    assert route.slice == :api_locations_photos
    assert route.plug == DawarichWeb.Api.PhotosController

    for {method, path, module, action} <- [
          {"POST", "/route_videos", DawarichWeb.RouteVideoActions, :create},
          {"DELETE", "/route_videos/42", DawarichWeb.RouteVideoActions, :destroy},
          {"POST", "/route_videos/42", DawarichWeb.RouteVideoActions, :destroy},
          {"PATCH", "/settings/visits", DawarichWeb.VisitSettingsActions, :update},
          {"PUT", "/settings/visits", DawarichWeb.VisitSettingsActions, :update},
          {"POST", "/settings/visits", DawarichWeb.VisitSettingsActions, :update},
          {"POST", "/visits/redetections", DawarichWeb.VisitSettingsActions, :redetect},
          {"PATCH", "/visits/bulk_update", DawarichWeb.VisitActions, :bulk_update},
          {"POST", "/visits/bulk_update", DawarichWeb.VisitActions, :bulk_update},
          {"DELETE", "/visits/bulk_destroy", DawarichWeb.VisitActions, :bulk_destroy},
          {"POST", "/visits/bulk_destroy", DawarichWeb.VisitActions, :bulk_destroy},
          {"POST", "/visits/merge", DawarichWeb.VisitActions, :merge},
          {"PATCH", "/visits/42", DawarichWeb.VisitActions, :update},
          {"PUT", "/visits/42", DawarichWeb.VisitActions, :update},
          {"DELETE", "/visits/42", DawarichWeb.VisitActions, :destroy},
          {"POST", "/visits/42", DawarichWeb.VisitActions, :member}
        ] do
      assert %{plug: ^module, plug_opts: ^action, pipe_through: [:a8_action]} =
               Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com")
    end

    for path <- ["/visits/not-a-number", "/visits/1234567890123456789", "/visits/42.json"] do
      replay(ctx, upstream, :post, path, "_method=delete")
    end
  end
end
