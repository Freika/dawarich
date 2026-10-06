defmodule DawarichWeb.A10cRoutesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.{Router, Strangler}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    RailsUser.insert!(%{
      id: 44001,
      email: "a10c-routes@example.invalid",
      settings: %{"locale" => "en"}
    })

    saved = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)
    server = RawHTTP.listen()
    upstream = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    pid =
      spawn(fn ->
        socket = RawHTTP.accept(server)
        RawHTTP.read_head(socket)
        RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 0\r\n\r\n")
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      Process.exit(pid, :kill)
      :gen_tcp.close(server.listen)
      Application.put_env(:dawarich, :rails_upstream, upstream)
    end)

    :ok
  end

  test "routes sharing and JSON deck actions outside page request filters" do
    for {method, path, plug, action} <- [
          {"PATCH", "/achievements/country_de/toggle_sharing",
           DawarichWeb.AchievementActions.Sharing, :sharing},
          {"POST", "/achievements/country_de/toggle_sharing",
           DawarichWeb.AchievementActions.Sharing, :sharing},
          {"POST", "/achievements/unlocks/next", DawarichWeb.AchievementActions.Unlocks, :next},
          {"POST", "/achievements/unlocks/42001/seen", DawarichWeb.AchievementActions.Unlocks,
           :seen},
          {"POST", "/achievements/unlocks/dismiss", DawarichWeb.AchievementActions.Unlocks,
           :dismiss}
        ] do
      route = Phoenix.Router.route_info(Router, method, path, "www.example.com")
      assert route.plug == plug and route.plug_opts == [action: action]
      assert route.pipe_through == [:achievement_action]

      conn =
        build_conn(method, path, "{}")
        |> put_req_header("accept", "application/json")
        |> Plug.Test.put_req_cookie(
          "_dawarich_session",
          RailsUser.cookie(RailsUser.session(44001))
        )

      assert Strangler.gate_open?(route, conn)
      result = Strangler.call(conn, [])
      refute result.halted
      refute Map.has_key?(result.private, :dawarich_raw_body)
    end
  end

  test "routes public HTML and PNG with shared and achievements rollback keys" do
    path = "/shared/achievements/a10c0000-0000-4000-8000-000000043001"
    route = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")
    assert route.plug == DawarichWeb.AchievementPublicPage
    assert route.rails_key == "achievements"
    assert route.pipe_through == [:achievement_public]

    for method <- ~w(GET HEAD),
        do:
          refute(
            Strangler.call(build_conn(method, path) |> put_req_header("accept", "text/html"), []).halted
          )

    image = Phoenix.Router.route_info(Router, "GET", path <> "/og.png", "www.example.com")
    assert image.plug == DawarichWeb.AchievementPublicImage
    assert image.rails_key == "achievements"
    assert image.pipe_through == [:achievement_image]

    for method <- ~w(GET HEAD) do
      conn = build_conn(method, path <> "/og.png") |> put_req_header("accept", "image/png")
      refute Strangler.call(conn, []).halted
    end

    for key <- ~w(shared achievements) do
      Application.put_env(:dawarich, :rails_routes, [key])
      assert_proxy(build_conn("GET", path))
      assert_proxy(build_conn("HEAD", path <> "/og.png"))
    end

    Application.put_env(:dawarich, :rails_routes, [])

    for path <-
          ~w(/settings/users/44001 /settings/users/export /settings/users/import /settings/background_jobs /admin/settings/test_geocoding /sidekiq /admin/flipper) do
      route = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")
      assert route == :error or route.plug != DawarichWeb.AchievementPublicPage
    end
  end

  defp assert_proxy(conn) do
    server = RawHTTP.listen()
    saved = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    task =
      Task.async(fn ->
        socket = RawHTTP.accept(server)
        RawHTTP.read_head(socket)
        RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 0\r\n\r\n")
        :gen_tcp.close(socket)
      end)

    result = Strangler.call(conn, [])
    assert result.status == 218 and result.halted
    Task.await(task)
    :gen_tcp.close(server.listen)
    Application.put_env(:dawarich, :rails_upstream, saved)
  end
end
